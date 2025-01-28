defmodule FullstackWeb.GroupChannel do
  use FullstackWeb, :channel
  alias FullstackWeb.Presence
  require Logger
  #  intercept(["user_joined"])

  @impl true
  def join("group:main", payload, socket) do
    if authorized?(socket.assigns) do
      send(self(), :after_join)
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  @impl true
  def handle_info(:after_join, socket) do
    {:ok, _} =
      Presence.track(socket, socket.assigns.mac_addr, %{
        online_at: inspect(System.system_time(:second)),
        mac_addr: socket.assigns.mac_addr
      })

    push(socket, "presence_state", Presence.list(socket))
    {:noreply, socket}
  end

  # Channels can be used in a request/response fashion
  # by sending replies to requests from the client
  @impl true
  def handle_in("ping", payload, socket) do
    Logger.info("Ping from #{inspect(payload)}")
    {:reply, {:ok, %{:ping => :pong}}, socket}
  end

  @impl true
  def handle_in("get_metrics", payload, socket) do
    Logger.info("Ping from #{inspect(payload)}")

    {:reply, {:ok, %{:metrics => <<104, 101, 108, 108, 111, 45, 119, 111, 114, 108, 100>>}},
     socket}
  end

  # It is also common to receive messages from the client and
  # broadcast to everyone in the current topic (group:lobby).
  @impl true
  def handle_in("shout", payload, socket) do
    broadcast(socket, "shout", payload)
    {:noreply, socket}
  end

  # Add authorization logic here as required.
  defp authorized?(%{:mac_addr => _macc_adrr} = payload) do
    true
  end
end
