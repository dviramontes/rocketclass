# Rocketclass

Local Rocket League video lab built with Elixir, Phoenix LiveView, SQLite, and a persistent Python/PyAV worker.

The first implementation decodes actual video frames, preserves presentation timestamps, records runs, and exports JSONL. **Video detection and tracking are not connected yet.** A Classify button sends the current frame to hosted Qwen vision, then classifies per-object evidence with hosted Laya. The optional synthetic overlay demo exercises playback; its boxes are generated geometry, not predictions or annotations.

## Run locally

Prerequisites: Elixir 1.18+ / Erlang OTP, and uv. Validated with Elixir 1.20.4 / OTP 29 on macOS arm64. Python 3.13.16 is selected by `.python-version`; `uv.lock` and `mix.lock` pin dependencies.

```sh
uv sync --locked
mix setup
mix phx.server
```

Open http://localhost:4000. Select a file from `data/`, choose **Inspect frames**, and start a run. The supplied `UuRhoADRFjo-middle-5s.mp4` is selected by default. Choose **Synthetic overlay demo** to check the canvas overlay. Click a completed run to play its video or export its frame records. Add more videos to `data/` and click **Refresh files**.

Video files stay local. Classify sends a captured JPEG to the configured vision server and the resulting text evidence to Laya. The server binds to loopback; the development session configuration is for local use. Playback is tested at the HTTP layer with H.264 MP4; other containers may decode in Python but require browser-compatible conversion, which is not implemented yet.

## Verification

```sh
mix test
uv run --locked pytest
mix format --check-formatted
node --check priv/static/app.js
```

With the web server stopped, exercise the supplied clip through the real Elixir/Python boundary:

```sh
mix run scripts/smoke.exs
```

Use one application instance per database. The smoke script creates two persisted runs, verifies artifact row counts, and prints their timing summaries. Automated Python tests generate a tiny video locally, so they need no downloaded footage or model weights.

## Implementation

- `lib/rocketclass/worker.ex`: supervised Port owner, one active job, request IDs, startup/stall deadlines, cancellation, explicit OS-process cleanup, and bounded restart backoff.
- `python/worker.py`: persistent reader plus a cancellable decoding thread. No child processes. Protocol output is four-byte big-endian length-prefixed JSON, capped at 1 MiB. Logs/errors never become protocol text on stdout.
- `lib/rocketclass/runs.ex`: SQLite run lifecycle. Interrupted runs are marked on startup; retries create new IDs.
- `lib/rocketclass_web/`: LiveView file selection, run history, playback and export routes.
- `priv/static/app.js`: timestamp-aligned canvas overlays. Assets are served locally without a JS bundler or CDN.

SQLite lives in `var/dev.db` (`var/test.db` for tests); artifacts live in `var/runs/<run-id>.jsonl`. Videos, runtime environments, and generated output are gitignored. Failed/cancelled partial artifacts are not served as completed results.

Each JSONL row records a frame index, dimensions, mode, and detections. `source_pts_ms` preserves the input PTS; `timestamp_ms` is relative to the first decoded video frame; `playback_timestamp_ms` is relative to the container start for video overlay alignment. The sample's offset within the original recording remains unverified. Inspection records have empty detections; demo records carry a `fixture-ball` track ID and a null detector score.

Current limits: playback loads the complete JSONL into browser memory, so use short clips. Videos are referenced in place, not copied or hashed; keep them unchanged for reproducibility. Worker timeouts can leave a `.partial` file after forced termination; only completed `.jsonl` artifacts are exposed. Adding inference subprocesses will require extending the current thread-only cancellation contract.

See [PLAN.md](PLAN.md) for the roadmap and [COMPATIBILITY.md](COMPATIBILITY.md) for measured results. Next: add detector/tracker adapters, evaluate a pretrained baseline on the sample, and agree situation labels before feeding video-derived observations to Laya.

## Frame classification

The server at `http://100.88.19.124:11434` exposes `laya:latest` with the `decision` capability. `/v1/models` lists models; classification uses **POST `/v1/systemone`**, not chat completions. This matches [Ollama’s decision API](https://ollama.com/blog/ollama-now-supports-jev-style-decision-models).

Select a run, seek to a frame, and click **Classify**. The browser pauses playback and captures a JPEG up to 960 pixels wide. `qwen3.5:35b` reads it using one fixed prompt that identifies visible cars, the game ball, and physical goals. It returns separate text evidence for each category. Laya then makes one typed decision per category: `present`, `absent`, or `unknown`. No prompt entry is required.

A provisional selected-label score below 0.6 produces `unknown`. This threshold has not been calibrated on gameplay. Results show their run ID and captured timestamp and remain session-only. The vision description can be wrong, and Laya can misclassify it. The pipeline does not locate objects, track movement, or prove scoring events.

```sh
# Defaults already point to the supplied server; override when needed.
LAYA_BASE_URL=http://100.88.19.124:11434/v1 LAYA_MODEL=laya:latest mix phx.server

# With the application server stopped:
mix run scripts/classify_frame.exs frame.jpg
```

The base URL must end in `/v1`, not `/v1/models`. Vision uses a 90-second request timeout. Laya uses a 15-second request timeout per category. Both use a 5-second connect timeout. Set `VISION_ENDPOINT` and `VISION_MODEL` to override the vision service. The browser remains responsive while classification runs. There are no automatic retries or fallback models. Tests mock the service and require no tailnet access.

`Rocketclass.Laya.classify/2` is the replaceable adapter. It accepts configurable criteria and instructions for future situation labels, validates the returned label distribution, and preserves the observation, criteria, endpoint, model, raw choice, scores, threshold, and abstention reason. Because inference is hosted remotely, the adapter runs in Elixir; Python remains responsible for video decoding and future vision inference. Frame results retain the run ID and captured playback timestamp but are not persisted as decision records. The `latest` model tag is mutable; pin model provenance before evaluating quality.


## Walkthrough and API visibility

Open [the five-slide HTML walkthrough](http://localhost:4000/assets/rocketclass-slides.html) while the server runs, or open `docs/rocketclass-slides.html` directly. It is self-contained, with keyboard navigation, fullscreen and print styles.

The **Latest classification API call** section updates as each vision or Laya request starts and finishes. It shows the endpoint, request JSON (with image bytes omitted), elapsed time, and the latest decoded response or error. Each new call replaces the previous entry. Logs remain in the current browser session and are not persisted. Laya returns one typed decision response, so this is live request status rather than token streaming.
