defmodule FullstackWeb.GroupChannel do
  use FullstackWeb, :channel

  @impl true
  def join("group:lobby", payload, socket) do
    if authorized?(payload) do
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  # Channels can be used in a request/response fashion
  # by sending replies to requests from the client
  @impl true
  def handle_in("ping", payload, socket) do
    {:reply, {:ok, %{:ping => :pong}}, socket}
  end

  # It is also common to receive messages from the client and
  # broadcast to everyone in the current topic (group:lobby).
  @impl true
  def handle_in("shout", payload, socket) do
    IO.inspect(payload, label: :to_broadcast)
    broadcast(socket, "shout", payload)
    {:noreply, socket}
  end

  # Add authorization logic here as required.
  defp authorized?(_payload) do
    true
  end
end
