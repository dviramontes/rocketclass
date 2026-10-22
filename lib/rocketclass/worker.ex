defmodule Rocketclass.Worker do
  use GenServer
  alias Rocketclass.{Protocol, Runs}

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  def analyze(source, mode), do: GenServer.call(__MODULE__, {:analyze, source, mode})
  def cancel, do: GenServer.call(__MODULE__, :cancel)
  def status, do: GenServer.call(__MODULE__, :status)

  def init(opts) do
    Process.flag(:trap_exit, true)
    send(self(), :boot)

    {:ok,
     %{
       port: nil,
       ready: false,
       buffer: <<>>,
       run: nil,
       timer: nil,
       backoff: 250,
       python: Keyword.get(opts, :python, Path.expand(".venv/bin/python")),
       script: Keyword.get(opts, :script, Path.expand("python/worker.py")),
       recover: Keyword.get(opts, :recover, true)
     }}
  end

  def handle_call(:status, _, s), do: {:reply, %{ready: s.ready, busy: s.run != nil}, s}

  def handle_call({:analyze, source, mode}, _, %{ready: true, run: nil} = s) do
    case Runs.create(source, mode) do
      {:ok, run} ->
        Port.command(
          s.port,
          Protocol.encode(%{
            type: "analyze",
            id: run.id,
            source: Path.expand(source),
            mode: mode,
            output: Runs.artifact(run.id)
          })
        )

        Phoenix.PubSub.broadcast(Rocketclass.PubSub, "runs", :runs_changed)
        {:reply, {:ok, run}, arm(%{s | run: run}, 30_000)}

      error ->
        {:reply, error, s}
    end
  end

  def handle_call({:analyze, _, _}, _, s), do: {:reply, {:error, :worker_unavailable_or_busy}, s}
  def handle_call(:cancel, _, %{run: nil} = s), do: {:reply, :ok, s}

  def handle_call(:cancel, _, s) do
    Port.command(s.port, Protocol.encode(%{type: "cancel", id: s.run.id}))
    {:reply, :ok, arm(%{s | run: Runs.update(s.run, status: "cancelling")}, 2_000)}
  end

  def handle_info(:boot, s) do
    if s.recover do
      # Migrations may not exist during `mix ecto.create` on first setup.
      if Ecto.Adapters.SQL.query(Rocketclass.Repo, "SELECT id FROM runs LIMIT 1", []) |> elem(0) ==
           :ok,
         do: Runs.interrupt_stale()
    end

    s = %{s | recover: false}

    try do
      port =
        Port.open({:spawn_executable, s.python}, [
          :binary,
          :exit_status,
          :use_stdio,
          :hide,
          args: [s.script]
        ])

      {:noreply, arm(%{s | port: port, buffer: <<>>, ready: false}, 10_000)}
    rescue
      _ -> {:noreply, restart(s, "Python worker unavailable; run uv sync")}
    end
  end

  def handle_info({port, {:data, data}}, %{port: port} = s) do
    case Protocol.feed(s.buffer <> data) do
      {:ok, messages, rest} ->
        {:noreply, Enum.reduce(messages, %{s | buffer: rest}, &message/2)}

      {:error, reason} ->
        {:noreply, restart(s, "Worker protocol error: #{reason}")}
    end
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = s),
    do: {:noreply, restart(s, "Worker exited (#{status})")}

  def handle_info({:EXIT, port, reason}, %{port: port} = s),
    do: {:noreply, restart(s, "Worker port closed: #{inspect(reason)}")}

  def handle_info({:timeout, ref}, %{timer: {_, ref}} = s),
    do: {:noreply, restart(s, "Worker timed out")}

  def handle_info(_, s), do: {:noreply, s}

  defp message(%{"type" => "ready"}, %{run: nil} = s),
    do: disarm(%{s | ready: true, backoff: 250})

  defp message(%{"id" => id, "type" => type} = m, %{run: %{id: id}} = s) do
    case type do
      "progress" ->
        if is_integer(m["frames"]) and m["frames"] >= 0 do
          next = %{s | run: Runs.update(s.run, frames: m["frames"])}
          if s.run.status == "cancelling", do: next, else: arm(next, 30_000)
        else
          restart(s, "Invalid progress")
        end

      "complete" ->
        if is_integer(m["frames"]) and is_map(m["summary"]) do
          finish(s, status: "complete", frames: m["frames"], summary: m["summary"])
        else
          restart(s, "Invalid completion")
        end

      "cancelled" ->
        finish(s, status: "cancelled")

      "error" ->
        finish(s, status: "failed", error: to_string(m["error"]))

      _ ->
        restart(s, "Unexpected worker message")
    end
  end

  defp message(_, s), do: restart(s, "Unexpected worker message or request ID")

  defp finish(s, attrs) do
    Runs.update(s.run, attrs)
    disarm(%{s | run: nil})
  end

  defp arm(s, ms) do
    s = disarm(s)
    ref = make_ref()
    %{s | timer: {Process.send_after(self(), {:timeout, ref}, ms), ref}}
  end

  defp disarm(%{timer: nil} = s), do: s

  defp disarm(s) do
    {timer, _} = s.timer
    Process.cancel_timer(timer)
    %{s | timer: nil}
  end

  defp restart(s, error) do
    kill(s.port)

    if s.run,
      do:
        Runs.update(s.run,
          status: if(s.run.status == "cancelling", do: "cancelled", else: "failed"),
          error: error
        )

    Process.send_after(self(), :boot, s.backoff)

    disarm(%{
      s
      | port: nil,
        ready: false,
        buffer: <<>>,
        run: nil,
        backoff: min(s.backoff * 2, 10_000)
    })
  end

  defp kill(nil), do: :ok

  defp kill(port) do
    # Worker creates threads only, no subprocess tree. Kill its OS process explicitly.
    case Port.info(port, :os_pid) do
      {:os_pid, pid} ->
        System.cmd("/bin/kill", ["-KILL", Integer.to_string(pid)], stderr_to_stdout: true)

      _ ->
        :ok
    end

    if Port.info(port), do: Port.close(port)
  rescue
    ArgumentError -> :ok
  end

  def terminate(_, s), do: kill(s.port)
end
