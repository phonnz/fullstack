defmodule FullstackWeb.GroupChannel do
  use FullstackWeb, :channel
  alias FullstackWeb.Presence
  #  intercept(["user_joined"])

  @impl true
  def join("group:main", payload, socket) do
    IO.inspect(payload, label: :payload)
    IO.inspect(socket.assigns, label: :join_assigns)

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

  @impl true
  def handle_in("ping", _payload, socket) do
    {:reply, {:ok, %{:ping => :pong}}, socket}
  end

  @impl true
  def handle_in("shout", payload, socket) do
    IO.inspect(payload, label: :to_broadcast)
    broadcast(socket, "shout", payload)
    {:noreply, socket}
  end

  @impl true
  def handle_in("stat", payload, socket) do
    IO.inspect(payload, label: :to_broadcast)

    {:noreply, socket}
  end

  # Add authorization logic here as required.
  defp authorized?(%{:mac_addr => _macc_adrr} = payload) do
    IO.inspect(payload, label: :authorizing)
    true
  end
end
