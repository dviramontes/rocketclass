defmodule Rocketclass.Protocol do
  @max 1_048_576
  def encode(message) do
    body = Jason.encode!(Map.put(message, :v, 1))
    <<byte_size(body)::32, body::binary>>
  end

  def feed(buffer), do: parse(buffer, [])
  defp parse(<<size::32, _::binary>>, _) when size > @max, do: {:error, :oversized_packet}

  defp parse(<<size::32, rest::binary>>, messages) when byte_size(rest) >= size do
    body = binary_part(rest, 0, size)
    tail = binary_part(rest, size, byte_size(rest) - size)

    case Jason.decode(body) do
      {:ok, %{"v" => 1, "type" => type} = message} when is_binary(type) ->
        parse(tail, [message | messages])

      _ ->
        {:error, :invalid_message}
    end
  end

  defp parse(rest, messages), do: {:ok, Enum.reverse(messages), rest}
end
