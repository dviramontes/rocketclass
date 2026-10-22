defmodule Rocketclass.LayaTest do
  use ExUnit.Case, async: true
  alias Rocketclass.Laya

  defp response(scores \\ %{"car" => 0.02, "ball" => 0.76, "goal" => 0.08, "unknown" => 0.14}) do
    %{
      "model" => "laya:latest",
      "answers" => %{
        "object" => %{
          "type" => "choice",
          "choice" => "ball",
          "probabilities" => scores,
          "confidence" => 0.67
        }
      }
    }
  end

  test "uses System One and preserves typed scores separately from final label" do
    transport = fn url, body, timeout ->
      assert url == "http://example.test:11434/v1/systemone"
      assert body.model == "laya:latest"
      assert body.state == "A spherical ball."
      assert body.questions.object.type == "choice"
      assert Map.has_key?(body.questions.object.criteria, "unknown")
      assert timeout == 15_000
      {:ok, response()}
    end

    assert {:ok, result} =
             Laya.classify("A spherical ball.",
               base_url: "http://example.test:11434/v1/",
               transport: transport
             )

    assert result.label == "ball"
    assert result.scores["ball"] == 0.76
    assert result.model_confidence == 0.67
    assert result.abstention_reason == nil
  end

  test "abstains on weak evidence without discarding the raw choice" do
    transport = fn _, _, _ ->
      {:ok, response(%{"car" => 0.2, "ball" => 0.4, "goal" => 0.2, "unknown" => 0.2})}
    end

    assert {:ok, result} = Laya.classify("Unclear object", transport: transport)
    assert result.label == "unknown"
    assert result.raw_choice == "ball"
    assert result.abstention_reason =~ "below threshold"
  end

  test "rejects invalid responses and propagates unavailable service" do
    for response <- [
          %{},
          response(%{"ball" => 1.0}),
          response(%{"car" => 0.0, "ball" => 3, "goal" => 0, "unknown" => 0})
        ] do
      assert {:error, _} = Laya.classify("A ball", transport: fn _, _, _ -> {:ok, response} end)
    end

    assert {:error, "offline"} =
             Laya.classify("A ball", transport: fn _, _, _ -> {:error, "offline"} end)
  end

  test "rejects missing observations, invalid schemas and model-list URLs before network access" do
    transport = fn _, _, _ -> flunk("Should not contact server") end

    for value <- ["", "   ", nil, String.duplicate("x", 4_001)] do
      assert {:error, _} = Laya.classify(value, transport: transport)
    end

    assert {:error, _} =
             Laya.classify("A ball",
               base_url: "http://example.test/v1/models",
               transport: transport
             )

    assert {:error, _} = Laya.classify("A ball", criteria: %{}, transport: transport)
  end

  test "reports pending and received events containing the latest request and response" do
    owner = self()
    callback = fn event -> send(owner, {:api_event, event}) end
    transport = fn _, _, _ -> {:ok, response()} end
    assert {:ok, _} = Laya.classify("A ball", transport: transport, on_event: callback)
    assert_received {:api_event, %{status: "pending", request: %{state: "A ball"}}}

    assert_received {:api_event,
                     %{status: "received", response: %{"answers" => _}, elapsed_ms: elapsed}}

    assert elapsed >= 0
  end
end
