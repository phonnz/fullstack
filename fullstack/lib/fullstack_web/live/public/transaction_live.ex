defmodule FullstackWeb.Public.TransactionLive do
  use FullstackWeb, :live_view
  alias Fullstack.Public.Transactions

  def mount(%{"id" => id}, _, socket) do
    socket =
      socket
      |> assign(:page_title, "Transaction Detail")
      |> assign(:transaction, Transactions.get(id))

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <.header><%= @page_title %> <%= @transaction.id %></.header>
    <.back navigate={~p"/transactions"}>go to transactions</.back>
    <pre>
      <%= inspect(@transaction, pretty: true) %>
    </pre>
    """
  end
end
