defmodule FullstackWeb.TransactionLive.Index do
  use FullstackWeb, :live_view

  alias Fullstack.Operations
  alias Fullstack.Financial.Transaction

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :transactions, Operations.list_transactions())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Transaction")
    |> assign(:transaction, Financial.get_transaction!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Transaction")
    |> assign(:transaction, %Transaction{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Transactions")
    |> assign(:transaction, nil)
  end

  @impl true
  def handle_info({FullstackWeb.TransactionLive.FormComponent, {:saved, transaction}}, socket) do
    {:noreply, stream_insert(socket, :transactions, transaction)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    transaction = Financial.get_transaction!(id)
    {:ok, _} = Financial.delete_transaction(transaction)

    {:noreply, stream_delete(socket, :transactions, transaction)}
  end
end
