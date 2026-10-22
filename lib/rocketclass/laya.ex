defmodule Rocketclass.Laya do
  @moduledoc "Remote typed decisions over textual observations; never a video detector."
  @criteria %{
    "car" => "A vehicle driven around the field",
    "ball" => "The spherical game ball",
    "goal" => "The physical goal structure or opening",
    "unknown" => "Insufficient information or another object"
  }
  @instructions "Classify the single described object. Use unknown when evidence is insufficient."

  def classify(observation, opts \\ []) do
    config = Keyword.merge(Application.get_env(:rocketclass, __MODULE__, []), opts)
    criteria = Keyword.get(config, :criteria, @criteria)
    threshold = Keyword.get(config, :threshold, 0.6)
    model = Keyword.get(config, :model, "laya:latest")

    base =
      Keyword.get(config, :base_url, "http://100.88.19.124:11434/v1") |> String.trim_trailing("/")

    uri = URI.parse(base)

    cond do
      not is_binary(observation) or String.trim(observation) == "" or
          byte_size(observation) > 4_000 ->
        {:error, "Enter an observation between 1 and 4,000 bytes."}

      not valid_criteria?(criteria) or not is_number(threshold) or threshold < 0 or threshold > 1 ->
        {:error, "Invalid classification schema or threshold."}

      uri.scheme not in ["http", "https"] or is_nil(uri.host) or uri.query != nil or
        uri.fragment != nil or uri.path != "/v1" ->
        {:error, "LAYA_BASE_URL must be an HTTP(S) base URL ending in /v1."}

      true ->
        body = %{
          model: model,
          state: observation,
          questions: %{
            object: %{
              type: "choice",
              instructions: Keyword.get(config, :instructions, @instructions),
              criteria: criteria
            }
          }
        }

        transport = Keyword.get(config, :transport, &request/3)

        endpoint = base <> "/systemone"
        notify = Keyword.get(config, :on_event, fn _ -> :ok end)
        started = System.monotonic_time(:millisecond)

        call = %{
          endpoint: endpoint,
          method: "POST",
          request: body,
          started_at: DateTime.to_iso8601(DateTime.utc_now()),
          status: "pending"
        }

        notify.(call)
        outcome = transport.(endpoint, body, Keyword.get(config, :timeout, 15_000))
        elapsed = System.monotonic_time(:millisecond) - started

        event =
          case outcome do
            {:ok, response} ->
              Map.merge(call, %{status: "received", response: response, elapsed_ms: elapsed})

            {:error, error} ->
              Map.merge(call, %{status: "failed", error: error, elapsed_ms: elapsed})
          end

        notify.(event)

        with {:ok, response} <- outcome,
             {:ok, result} <- parse(response, criteria, threshold, model) do
          {:ok,
           Map.merge(result, %{
             observation: observation,
             criteria: criteria,
             threshold: threshold,
             endpoint: base <> "/systemone"
           })}
        end
    end
  end

  defp valid_criteria?(criteria) do
    is_map(criteria) and map_size(criteria) in 2..20 and Map.has_key?(criteria, "unknown") and
      Enum.all?(criteria, fn {key, value} -> is_binary(key) and is_binary(value) end)
  end

  defp request(url, body, timeout) do
    case :httpc.request(
           :post,
           {String.to_charlist(url), [], ~c"application/json", Jason.encode!(body)},
           [timeout: timeout, connect_timeout: min(timeout, 5_000), autoredirect: false],
           body_format: :binary
         ) do
      {:ok, {{_, 200, _}, _, response}} when byte_size(response) <= 1_048_576 ->
        case Jason.decode(response) do
          {:ok, decoded} -> {:ok, decoded}
          _ -> {:error, "Laya returned invalid JSON."}
        end

      {:ok, {{_, status, _}, _, _}} ->
        {:error, "Laya returned HTTP #{status}."}

      {:error, _} ->
        {:error,
         "Could not reach Laya within the request deadline. Check the server and tailnet connection."}
    end
  end

  defp parse(
         %{
           "model" => model,
           "answers" => %{
             "object" => %{
               "type" => "choice",
               "choice" => choice,
               "probabilities" => scores,
               "confidence" => confidence
             }
           }
         },
         criteria,
         threshold,
         expected
       ) do
    valid =
      model == expected and is_map(scores) and Map.has_key?(criteria, choice) and
        Enum.sort(Map.keys(scores)) == Enum.sort(Map.keys(criteria)) and
        Enum.all?(scores, fn {_, value} -> is_number(value) and value >= 0 and value <= 1 end) and
        is_number(confidence) and confidence >= 0 and confidence <= 1

    if valid and abs(Enum.sum(Map.values(scores)) - 1) < 0.01 do
      abstain = choice == "unknown" or scores[choice] < threshold

      {:ok,
       %{
         model: model,
         label: if(abstain, do: "unknown", else: choice),
         raw_choice: choice,
         scores: scores,
         model_confidence: confidence,
         abstention_reason:
           cond do
             choice == "unknown" -> "Model selected unknown"
             abstain -> "Selected-label score is below threshold"
             true -> nil
           end
       }}
    else
      {:error, "Laya returned an invalid decision or label distribution."}
    end
  end

  defp parse(_, _, _, _), do: {:error, "Laya returned an unexpected decision schema."}
end
