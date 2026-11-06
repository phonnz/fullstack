defmodule FullstackWeb.GroupChannelTest do
  use FullstackWeb.ChannelCase

  setup do
    {:ok, _, socket} =
      FullstackWeb.UserSocket
      |> socket("user_id", %{mac_addr: "AA:BB:CC:DD:EE:FF"})
      |> subscribe_and_join(FullstackWeb.GroupChannel, "group:main")

    %{socket: socket}
  end

  test "ping replies with status ok", %{socket: socket} do
    ref = push(socket, "ping", %{"hello" => "there"})
    assert_reply ref, :ok, %{ping: :pong}
  end

  test "shout broadcasts to group:main", %{socket: socket} do
    push(socket, "shout", %{"hello" => "all"})
    assert_broadcast "shout", %{"hello" => "all"}
  end

  test "broadcasts are pushed to the client", %{socket: socket} do
    broadcast_from!(socket, "broadcast", %{"some" => "data"})
    assert_push "broadcast", %{"some" => "data"}
  end
end
