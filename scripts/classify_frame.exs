case System.argv() do
  [path] ->
    image = "data:image/jpeg;base64," <> Base.encode64(File.read!(path))
    callback = fn event -> IO.puts(:stderr, "#{event[:stage]} #{event.status} #{event[:object]}") end
    case Rocketclass.FrameClassifier.classify(image, on_event: callback) do
      {:ok, result} -> IO.puts(Jason.encode!(result, pretty: true))
      {:error, error} -> IO.puts(:stderr, error); System.halt(1)
    end
  _ -> IO.puts(:stderr, "Usage: mix run scripts/classify_frame.exs frame.jpg"); System.halt(1)
end
