defmodule Rocketclass.FrameClassifierTest do
  use ExUnit.Case, async: true
  alias Rocketclass.FrameClassifier

  test "uses a fixed vision prompt then classifies every category without exposing image data in logs" do
    owner = self()

    vision = fn _, body, _ ->
      assert body.think == false
      assert hd(body.messages).content == FrameClassifier.prompt()
      assert hd(body.messages).images == ["/9j/"]

      {:ok,
       %{
         "message" => %{
           "content" =>
             Jason.encode!(%{
               car: "A car is visible.",
               ball: "A ball is visible.",
               goal: "The goal is unclear."
             })
         }
       }}
    end

    laya = fn _, body, _ ->
      assert body.state in [
               "car: A car is visible.",
               "ball: A ball is visible.",
               "goal: The goal is unclear."
             ]

      send(owner, :classified)

      {:ok,
       %{
         "model" => "laya:latest",
         "answers" => %{
           "object" => %{
             "type" => "choice",
             "choice" => "unknown",
             "probabilities" => %{"present" => 0.1, "absent" => 0.1, "unknown" => 0.8},
             "confidence" => 0.7
           }
         }
       }}
    end

    assert {:ok, result} =
             FrameClassifier.classify("data:image/jpeg;base64,/9j/",
               transport: vision,
               laya_options: [transport: laya],
               on_event: fn event -> send(owner, event) end
             )

    assert Map.keys(result.objects) |> Enum.sort() == ["ball", "car", "goal"]
    assert result.objects["goal"].label == "unknown"
    assert_received %{stage: "vision", status: "pending", request: request}
    assert hd(request.messages).images == ["JPEG frame (3 bytes)"]
    for _ <- 1..3, do: assert_received(:classified)
  end

  test "bad frames and vision failures never reach Laya" do
    laya = fn _, _, _ -> flunk("No classification without visual evidence") end
    assert {:error, _} = FrameClassifier.classify("invalid", laya_options: [transport: laya])

    for response <- [{:error, "offline"}, {:ok, %{}}, {:ok, %{"message" => %{"content" => ""}}}] do
      assert {:error, _} =
               FrameClassifier.classify("data:image/jpeg;base64,/9j/",
                 transport: fn _, _, _ -> response end,
                 laya_options: [transport: laya]
               )
    end
  end
end
