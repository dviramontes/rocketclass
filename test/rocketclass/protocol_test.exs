defmodule Rocketclass.ProtocolTest do
  use ExUnit.Case, async: true
  alias Rocketclass.Protocol

  test "reassembles every possible split and preserves multiple messages" do
    packet = Protocol.encode(%{type: "ready"})

    for split <- 0..(byte_size(packet) - 1) do
      left = binary_part(packet, 0, split)
      right = binary_part(packet, split, byte_size(packet) - split)
      assert {:ok, [], buffer} = Protocol.feed(left)

      assert {:ok, [%{"type" => "ready"}, %{"type" => "ready"}], <<>>} =
               Protocol.feed(buffer <> right <> packet)
    end
  end

  test "rejects oversized frames and malformed or unversioned JSON" do
    assert {:error, :oversized_packet} = Protocol.feed(<<2_000_000::32>>)
    assert {:error, :invalid_message} = Protocol.feed(<<1::32, "{">>)
    assert {:error, :invalid_message} = Protocol.feed(<<2::32, "{}">>)
  end
end
