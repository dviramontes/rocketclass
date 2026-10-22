# Initial compatibility spike

Measured locally on 2026-10-21 (America/New_York): Apple M5, 24 GiB RAM, macOS arm64. Elixir 1.20.4, Erlang/OTP 29, Python 3.13.16, PyAV 16.1.0. Exact application dependency versions are in the lockfiles.

Input: `data/UuRhoADRFjo-middle-5s.mp4`, H.264, 1920 × 1080, approximately 29.97 fps, container duration 5.005 seconds.

| Run | Decoded frames | Worker processing time | Decode + JSONL throughput |
| --- | ---: | ---: | ---: |
| Inspect frames | 149 | 0.680 s | 219.2 fps |
| Synthetic overlay demo | 149 | 0.653 s | 228.0 fps |

These are single smoke measurements through the real Port worker, not statistical benchmarks or inference results. They include opening/decoding the file and writing JSONL, exclude Python process startup, and do not measure model latency, memory, GPU support, or UI playback performance. The two modes ran sequentially in one persistent worker.

First video PTS: 33.367 ms. Last timestamp relative to the first decoded video frame: 4938.267 ms. Container duration and decoded frame span differ; do not derive timestamps from a nominal frame rate.

Verified: Python decoding/timestamps, fragmented protocol reads, malformed packet rejection, persisted completion, cancellation, crash recovery, stall deadlines, forced termination of an unresponsive worker, LiveView run selection, exports, static assets, and HTTP range requests for seeking. Full interactive browser playback remains a manual check: native Chrome automation was interrupted by concurrent user activity.

PyTorch, YOLO, and ByteTrack are not installed or evaluated in this slice. Laya is hosted remotely and requires no local installation. No claim of detection quality or inference speed is supported yet. Full milestone 1 remains open until those compatibility and model checks are complete.


## Remote Laya connectivity

Verified `laya:latest` from `http://100.88.19.124:11434/v1/models`. Model metadata advertises `decision` only, ModernBERT, 421.03M parameters, BF16. The chat-completions route rejects this model; `/v1/systemone` accepts typed choice questions.

A live request through `Rocketclass.Laya.classify/2` classified the synthetic observation “A spherical ball is visible above the playing field.” as `ball`, with selected-label score 0.7307. This is a connectivity/schema smoke test, not a gameplay evaluation. The request transmits only the observation and label criteria; no video was sent. Domain-specific calibration, immutable model provenance, and persisted video-window classification remain pending.


## Single-frame classification prototype

The Classify button now captures the displayed video frame and sends a JPEG to `qwen3.5:35b` at `/api/chat` using a fixed prompt. Qwen returns per-category textual evidence, which the adapter sends to Laya for separate presence decisions. Native Ollama metadata confirms Qwen's vision capability. The latest API panel displays pending and received states, with image bytes omitted from logs.

A browser smoke test completed on the supplied sample at 0.0 seconds. All three categories returned `unknown` under the provisional 0.6 threshold. Other smoke requests exposed inconsistent Laya decisions, including contradictions of explicit vision descriptions. This validates the request flow, not classification quality. Evaluate prompt/schema compatibility and held-out frames before relying on results. The pipeline does not emit bounding boxes or tracks. Seventeen Elixir tests cover the updated UI and adapters.
