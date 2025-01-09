defmodule FullstackWeb.Public.TransactionsLive.PublicTransactions do
  use FullstackWeb, :live_view

  import FullstackWeb.CustomComponents
  alias Fullstack.Financial

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Fullstack.PubSub, "centralized_counter")
    end

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket =
      socket
      |> assign(:info, Financial.build_transactions_analytics(params))
      |> assign(:form, to_form(params))

    {:noreply, socket}
  end
end
