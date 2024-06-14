defmodule FullstackWeb.CustomerLive.Show do
  use FullstackWeb, :live_view

  alias Fullstack.Customers

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    {:noreply,
     socket
     |> assign(:page_title, page_title(socket.assigns.live_action))
     |> assign(:customer, Customers.get_customer!(id))}
  end

  defp page_title(:show), do: "Show Customer"
  defp page_title(:edit), do: "Edit Customer"
end
