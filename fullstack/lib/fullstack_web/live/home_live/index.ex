defmodule FullstackWeb.HomeLive.Index do
  alias Fullstack.Financial
  use Phoenix.LiveView

  alias Fullstack.Customers
  alias Fullstack.Financial

  @impl true
  def mount(params, _, socket) do
    IO.inspect(params, label: :PARAMS)

    socket =
      socket
      |> assign(:feature, random_feature())
      |> assign(:transactions_count, transactions_count())
      |> assign(:customers_count, customers_count())
      |> assign(:counter, 0)
      |> assign(:arcade, params["arcade"])

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    IO.inspect(params, label: :handel_params)

    if Map.has_key?(params, :arcade) do
      socket =
        socket
        |> put_flash(:warning, "Validating User for Device #{params.arcade}")
        |> put_flash(:info, "Calling Arcade #{params.arcade}")
    end

    {:noreply, socket}
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
