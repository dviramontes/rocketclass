defmodule RocketclassWeb.HomeLive do
  use Phoenix.LiveView
  alias Rocketclass.{Runs, Worker}

  def mount(_, _, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Rocketclass.PubSub, "runs")

    {:ok,
     assign(socket,
       sources: Runs.sources(),
       runs: Runs.list(),
       selected: nil,
       error: nil,
       classification: nil,
       classifying: false,
       classification_error: nil,
       latest_api_call: nil,
       api_call_ref: nil
     )}
  end

  def handle_event("refresh", _, socket), do: {:noreply, assign(socket, sources: Runs.sources())}

  def handle_event("analyze", %{"source" => source, "mode" => mode}, socket) do
    case Worker.analyze(source, mode) do
      {:ok, run} -> {:noreply, assign(socket, selected: run, runs: Runs.list(), error: nil)}
      {:error, reason} -> {:noreply, assign(socket, error: "Could not start: #{inspect(reason)}")}
    end
  end

  def handle_event("select", %{"id" => id}, socket),
    do: {:noreply, assign(socket, selected: Runs.get(id))}

  def handle_event("cancel", _, socket) do
    Worker.cancel()
    {:noreply, socket}
  end

  def handle_event("classify_frame", _, %{assigns: %{classifying: true}} = socket),
    do: {:noreply, socket}

  def handle_event(
        "classify_frame",
        %{"image" => image, "run_id" => run_id, "timestamp" => timestamp},
        socket
      )
      when is_number(timestamp) and timestamp >= 0 do
    if socket.assigns.selected && socket.assigns.selected.id == run_id do
      owner = self()
      ref = make_ref()

      {:noreply,
       socket
       |> assign(
         classifying: true,
         classification: nil,
         classification_error: nil,
         api_call_ref: ref,
         latest_api_call: %{status: "validating"}
       )
       |> start_async(:classification, fn ->
         case Rocketclass.FrameClassifier.classify(image,
                on_event: fn event -> send(owner, {:laya_api_call, ref, event}) end
              ) do
           {:ok, result} -> {:ok, Map.merge(result, %{run_id: run_id, timestamp: timestamp})}
           error -> error
         end
       end)}
    else
      {:noreply, assign(socket, classification_error: "Select the video you want to classify.")}
    end
  end

  def handle_event("classify_frame", _, socket),
    do: {:noreply, assign(socket, classification_error: "No valid frame is available.")}

  def handle_event("frame_capture_error", %{"error" => error}, socket),
    do: {:noreply, assign(socket, classification_error: error)}

  def handle_async(:classification, {:ok, {:ok, result}}, socket),
    do: {:noreply, assign(socket, classifying: false, classification: result)}

  def handle_async(:classification, {:ok, {:error, error}}, socket) do
    call = Map.merge(socket.assigns.latest_api_call || %{}, %{status: "failed", error: error})

    {:noreply,
     assign(socket, classifying: false, classification_error: error, latest_api_call: call)}
  end

  def handle_async(:classification, {:exit, _}, socket),
    do:
      {:noreply,
       assign(socket,
         classifying: false,
         classification_error: "Classification failed. Please retry.",
         latest_api_call:
           Map.merge(socket.assigns.latest_api_call || %{}, %{
             status: "failed",
             error: "Classification task exited"
           })
       )}

  def handle_info({:laya_api_call, ref, event}, %{assigns: %{api_call_ref: ref}} = socket),
    do: {:noreply, assign(socket, latest_api_call: event)}

  def handle_info({:laya_api_call, _, _}, socket), do: {:noreply, socket}

  def handle_info(:runs_changed, socket) do
    selected = if socket.assigns.selected, do: Runs.get(socket.assigns.selected.id)
    {:noreply, assign(socket, runs: Runs.list(), selected: selected)}
  end

  def render(assigns) do
    ~H"""
    <main>
      <header>
        <span class="eyebrow">LOCAL VIDEO LAB / 001</span><h1>
          Rocketclass<span> / replay lab</span>
        </h1><p>Inspect the frames. Build the detector. Understand the play.</p>
      </header>
      <section class="import">
        <div>
          <h2>Start a run</h2><p>Choose a video from <code>data/</code>.</p>
        </div>
        <form phx-submit="analyze">
          <label>Source video<select name="source" required><option
            :for={source <- @sources}
            value={source}
            selected={String.contains?(source, "middle-5s")}
          >
            {Path.basename(source)}
          </option></select></label>
          <label>Analysis mode<select name="mode"><option value="inspect">
            Inspect frames · no detector
          </option><option value="fixture">Synthetic overlay demo · not predictions</option></select></label>
          <button disabled={@sources == []}>Start run →</button>
        </form>
        <button class="quiet" phx-click="refresh">Refresh files</button>
        <p :if={@error} role="alert" class="error">{@error}</p>
      </section>
      <div class="workspace">
        <aside>
          <h2>Recent runs <small>{length(@runs)}</small></h2><p :if={@runs == []}>
            Your first run will appear here.
          </p>
          <button
            :for={run <- @runs}
            class={if @selected && @selected.id == run.id, do: "run active", else: "run"}
            phx-click="select"
            phx-value-id={run.id}
          >
            <strong>{Path.basename(run.source)}</strong><span>{run.mode} · {run.status} · {run.frames} frames</span><small>{Calendar.strftime(
              run.inserted_at,
              "%H:%M:%S UTC"
            )}</small>
          </button>
        </aside>
        <section class="viewer">
          <%= if @selected do %>
            <div class="viewer-title">
              <h2>{Path.basename(@selected.source)}</h2><span class="badge">{@selected.status}</span>
            </div>
            <p class="notice">
              {if @selected.mode == "fixture",
                do: "SYNTHETIC DEMO — boxes are generated geometry, not detections or annotations.",
                else: "FRAME INSPECTION — real decoding and timestamps. No detector is connected yet."}
            </p>
            <div
              id={"playback-#{@selected.id}"}
              phx-hook="Playback"
              data-run-id={@selected.id}
              data-results={
                if @selected.status == "complete", do: "/runs/#{@selected.id}/results", else: ""
              }
            >
              <div class="stage" id={"stage-#{@selected.id}"} phx-update="ignore">
                <video controls preload="metadata" src={"/runs/#{@selected.id}/video"}></video><canvas></canvas>
              </div>
              <p class="playback-status" data-playback-status></p>
            </div>
            <p :if={@selected.error} class="error">{@selected.error}</p>
            <button
              :if={@selected.status in ["running", "cancelling"]}
              phx-click="cancel"
              disabled={@selected.status == "cancelling"}
            >Cancel run</button>
            <div :if={@selected.status == "complete"} class="metrics">
              <div><strong>{@selected.frames}</strong><span>decoded frames</span></div><div>
                <strong>{Float.round(@selected.summary["elapsed_seconds"] || 0.0, 3)}s</strong><span>processing time</span>
              </div><div>
                <strong>{@selected.summary["width"]} × {@selected.summary["height"]}</strong><span>source dimensions</span>
              </div><a href={"/runs/#{@selected.id}/results"} download={"#{@selected.id}.jsonl"}>Export JSONL ↗</a>
            </div>
          <% else %>
            <div class="empty">
              <span>01 / LOAD A REPLAY</span><h2>A closer look at every frame.</h2><p>
                Start with frame inspection to verify decoding and timing. Use the synthetic demo to exercise synchronized overlays.
              </p>
            </div>
          <% end %>
        </section>
      </div>
      <section class="import classifier">
        <h2>Frame classification</h2>
        <p>
          Select a run and pause or seek to a frame. Classify sends that frame to your vision server, then Laya classifies whether cars, a ball, and a goal are visible.
        </p>
        <button
          id="classify-frame"
          phx-click={Phoenix.LiveView.JS.dispatch("rocketclass:classify-frame")}
          disabled={@classifying || is_nil(@selected)}
        >{if @classifying, do: "Classifying…", else: "Classify"}</button>
        <p :if={@classification_error} role="alert" class="error">{@classification_error}</p>
        <div :if={@classification} class="classification-result">
          <h3>Frame at {Float.round(@classification.timestamp * 1.0, 3)} s</h3>
          <p>Run {@classification.run_id}</p>
          <ul>
            <li :for={{object, result} <- Enum.sort(@classification.objects)}>
              <strong>{object}: {result.label}</strong><br />Laya score: {Float.round(
                result.scores[result.raw_choice] * 100,
                1
              )}%<span :if={result.abstention_reason}><br />{result.abstention_reason}</span>
            </li>
          </ul>
          <p>
            Model judgments need validation. This classifies presence in one frame, not object locations or motion.
          </p>
        </div>
      </section>
      <section class="import api-log" aria-labelledby="api-log-title">
        <h2 id="api-log-title">Latest classification API call</h2>
        <p :if={is_nil(@latest_api_call)}>
          Click Classify to see the latest vision or Laya request and response.
        </p>
        <div :if={@latest_api_call}>
          <p role="status">
            {@latest_api_call.status} {@latest_api_call[:stage]} {@latest_api_call[:object]}<span :if={
              @latest_api_call[:elapsed_ms]
            }> · {@latest_api_call.elapsed_ms} ms</span>
          </p>
          <p :if={@latest_api_call[:endpoint]}><code>POST {@latest_api_call.endpoint}</code></p>
          <details :if={@latest_api_call[:request]}>
            <summary>Request JSON</summary><pre>{Jason.encode!(@latest_api_call.request, pretty: true)}</pre>
          </details>
          <h3>Response</h3>
          <pre id="latest-api-response">{cond do
            @latest_api_call[:response] -> Jason.encode!(@latest_api_call.response, pretty: true)
            @latest_api_call[:error] -> Jason.encode!(%{error: @latest_api_call.error}, pretty: true)
            true -> "Waiting for response…"
          end}</pre>
          <p :if={@latest_api_call[:response] && @latest_api_call[:error]} class="error">
            {@latest_api_call.error}
          </p>
        </div>
      </section>
      <footer>Local video files · Remote Laya text classification · Video detection pending</footer>
    </main>
    """
  end
end
