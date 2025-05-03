defmodule FullstackWeb.Public.TransactionsTableLive do
  alias Phoenix.LiveView.AsyncResult
  use FullstackWeb, :live_view
  alias Fullstack.Public.Transactions
  alias Money

  @valid_status [
    :inserted,
    :started,
    :on_going,
    :ended,
    :uploading,
    :failed,
    :processing,
    :inferred,
    :outstanding,
    :paid,
    :rejected,
    :cancelled
  ]

  def mount(_, _, socket) do
    socket =
      socket
      |> assign(:page_title, "Transactions")

    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    socket =
      socket
      |> assign_async(
        :transactions,
        fn ->
          case Transactions.list_transactions(params) do
            {:error, reason} ->
              {:error, reason}

            transactions ->
              transactions
          end
        end,
        on_success: &handle_transactions_success/2,
        on_failure: &handle_transactions_failure/2,
        reset: true
      )
      |> assign(:valid_status, @valid_status)
      |> assign(:form, to_form(params))

    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <.header><%= @page_title %></.header>
    <.simple_form
      for={@form}
      phx-change="filter"
      autocomplete="off"
      phx-debounce="500"
      class="filters"
    >
      <.input field={@form[:query_filter]} placeholder="customer_id..." />
      <.input type="select" field={@form[:status]} prompt="Status" options={@valid_status} />
    </.simple_form>
    <.link patch={~p"/transactions"}>
      <.icon name="hero-x-mark text-blue-700" class="w-4 h-4" />
    </.link>
    <div :if={@transactions.loading} class="loading">
      <div class="text-amber-700 spinner">Loading</div>
    </div>
    <div :if={@transactions.failed} class="error">
      <div class="text-red-700 spinner">
        <.icon name="hero-exclamation-triangle-mini text-red-700" class="w-4 h-4" /><%= elem(
          @transactions.failed,
          1
        ) %>
      </div>
    </div>
    <.table :if={@transactions.ok?} id="transactions" rows={@transactions.result}>
      <:col :let={transaction} label="Id">
        <.link navigate={~p"/transactions/#{transaction.id}"}>
          <%= transaction.inserted_at %><br />
          <%= transaction.id %>
        </.link>
      </:col>
      <:col :let={transaction} label="Customer"><%= transaction.customer_id %></:col>
      <:col :let={transaction} label="Status">
        <span class={[
          "rounded-md px-2 py-1 text-xs font-medium uppercase inline-block border",
          transaction.status == :ended && "text-lime-600 border-lime-600",
          transaction.status in [:inserted, :on_going] && "text-amber-600 border-amber-600",
          transaction.status == :cancelled && "text-gray-600 border-gray-600"
        ]}>
          <%= transaction.status %>
        </span>
      </:col>
      <:col :let={transaction} label="Amount">
        <%= transaction.amount |> Money.new() |> Money.to_string() %>
      </:col>
    </.table>
    """
  end

  def handle_event("filter", params, socket) do
    params =
      params
      |> Map.take(~w(query_filter status))
      |> Map.reject(fn {_, v} -> v == "" end)

    socket = push_patch(socket, to: ~p"/transactions?#{params}")

    {:noreply, socket}
  end

  def handle_transactions_success(transactions, socket) do
    assign(socket, :transactions, %{loaded: true, data: transactions})
  end

  # Failure handler
  def handle_transactions_failure(error, socket) do
    assign(socket, :transactions, %{failed: true, error: error})
  end
end
