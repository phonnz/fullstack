defmodule FullstackWeb.Public.TransactionsTableLive do
  use FullstackWeb, :live_view

  def mount(_, _, socket) do
    socket =
      socket
      |> assign(:page_title, "Transactions")
      |> assign(:transactions, [])

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <.header><%= @page_title %></.header>
    <.table id="transactions" rows={@transactions}>
      <:col :let={transaction} label="id"><%= transaction.id %></:col>
    </.table>
    """
  end
end
