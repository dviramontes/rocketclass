alias Rocketclass.{Worker, Runs}
wait = fn fun ->
  Enum.reduce_while(1..200, nil, fn _, _ ->
    case fun.() do
      false -> Process.sleep(50); {:cont, nil}
      value -> {:halt, value}
    end
  end) || raise "Timed out"
end
wait.(fn -> Worker.status().ready end)
for mode <- ["inspect", "fixture"] do
  {:ok, run} = Worker.analyze("data/UuRhoADRFjo-middle-5s.mp4", mode)
  result = wait.(fn ->
    current = Runs.get(run.id)
    if current.status in ["complete", "failed"], do: current, else: false
  end)
  if result.status != "complete", do: raise(result.error)
  rows = File.stream!(Runs.artifact(run.id)) |> Enum.map(&Jason.decode!/1)
  if length(rows) != result.frames, do: raise("Frame count mismatch")
  IO.puts(Jason.encode!(%{id: result.id, mode: mode, frames: result.frames, summary: result.summary}))
end
