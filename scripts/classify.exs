observation = System.argv() |> Enum.join(" ")
case Rocketclass.Laya.classify(observation) do
  {:ok, result} -> IO.puts(Jason.encode!(result, pretty: true))
  {:error, error} -> IO.puts(:stderr, error); System.halt(1)
end
