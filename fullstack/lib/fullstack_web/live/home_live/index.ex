defmodule FullstackWeb.HomeLive.Index do
  alias Fullstack.Financial
  use Phoenix.LiveView

  alias Fullstack.Customers
  alias Fullstack.Financial

  @impl true
  def mount(_params, _, socket) do
    socket =
      socket
      |> assign(:feature, random_feature())
      |> assign(:transactions_count, transactions_count())
      |> assign(:customers_count, customers_count())
      |> assign(:counter, 0)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    IO.inspect(params, label: :PARAMS)

    case Map.fetch(params, "short_url") do
      {:ok, _url} ->
        {:noreply, redirect(socket, to: "/")}

      :error ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("inc", params, %{:assigns => %{:counter => counter}} = socket) do
    IO.inspect(params, label: :handle_params)

    {:noreply, assign(socket, :counter, counter + 1)}
  end

  @impl true
  def handle_event("dec", params, %{:assigns => %{:counter => counter}} = socket) do
    IO.inspect(params, label: :handle_params)

    {:noreply, assign(socket, :counter, counter - 1)}
  end

  defp random_feature(), do: "real-time"
  defp transactions_count(), do: Financial.transactions_count()
  defp customers_count(), do: Customers.customers_count()
end
