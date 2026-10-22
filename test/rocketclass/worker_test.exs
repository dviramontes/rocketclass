defmodule Rocketclass.WorkerTest do
  use ExUnit.Case, async: false
  alias Rocketclass.{Worker, Runs}

  setup do
    name = :test_worker

    pid =
      start_supervised!(
        {Worker, name: name, script: Path.expand("test/support/fake_worker.py"), recover: false}
      )

    wait(fn -> GenServer.call(pid, :status).ready end)
    {:ok, pid: pid}
  end

  defp source(tag) do
    path = "data/test-#{tag}-#{System.unique_integer([:positive])}.mp4"
    File.write!(path, "fixture")
    on_exit(fn -> File.rm(path) end)
    path
  end

  defp wait(fun, tries \\ 100)
  defp wait(_fun, 0), do: flunk("Timed out waiting for worker")

  defp wait(fun, tries) do
    if fun.(),
      do: :ok,
      else:
        (
          Process.sleep(25)
          wait(fun, tries - 1)
        )
  end

  test "persists success and accepts a subsequent run", %{pid: pid} do
    path = source("success")
    {:ok, run} = GenServer.call(pid, {:analyze, path, "inspect"})
    wait(fn -> Runs.get(run.id).status == "complete" end)
    assert {:ok, _} = GenServer.call(pid, {:analyze, path, "fixture"})
  end

  test "rejects concurrent jobs and cancels the active run", %{pid: pid} do
    path = source("wait")
    {:ok, run} = GenServer.call(pid, {:analyze, path, "inspect"})

    assert {:error, :worker_unavailable_or_busy} =
             GenServer.call(pid, {:analyze, path, "inspect"})

    assert :ok = GenServer.call(pid, :cancel)
    wait(fn -> Runs.get(run.id).status == "cancelled" end)
    assert GenServer.call(pid, :status).ready
  end

  test "malformed output and crashes fail runs and restart worker", %{pid: pid} do
    for kind <- ["malformed", "crash"] do
      {:ok, run} = GenServer.call(pid, {:analyze, source(kind), "inspect"})
      wait(fn -> Runs.get(run.id).status == "failed" end)
      wait(fn -> GenServer.call(pid, :status).ready end)
      assert Process.alive?(pid)
    end
  end

  test "cancel timeout kills an unresponsive worker", %{pid: pid} do
    {:ok, run} = GenServer.call(pid, {:analyze, source("hang"), "inspect"})
    port = :sys.get_state(pid).port
    {:os_pid, os_pid} = Port.info(port, :os_pid)
    GenServer.call(pid, :cancel)
    wait(fn -> Runs.get(run.id).status == "cancelled" end, 150)
    {_, status} = System.cmd("/bin/kill", ["-0", to_string(os_pid)], stderr_to_stdout: true)
    assert status != 0
    wait(fn -> GenServer.call(pid, :status).ready end)
  end

  test "stalled jobs fail on deadline while stale timers are ignored", %{pid: pid} do
    {:ok, run} = GenServer.call(pid, {:analyze, source("wait"), "inspect"})
    send(pid, {:timeout, make_ref()})
    assert GenServer.call(pid, :status).busy
    {_, ref} = :sys.get_state(pid).timer
    send(pid, {:timeout, ref})
    wait(fn -> Runs.get(run.id).status == "failed" end)
    assert Runs.get(run.id).error == "Worker timed out"
    wait(fn -> GenServer.call(pid, :status).ready end)
  end
end
