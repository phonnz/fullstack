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
      |> assign(:devices_count, 1)
      |> assign(:local, 0)
      |> assign(:identified, 0)
      |> assign(:shared, 0)
      |> assign(:arcade, params["arcade"])

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("inc", %{"id" => counter_id}, socket) do
    {counter, value} = get_counter(counter_id, socket)
    dbg(counter)
    {:noreply, assign(socket, counter, value + 1)}
  end

  @impl true
  def handle_event("dec", %{"id" => counter_id}, socket) do
     {counter, value} = get_counter(counter_id, socket)
    dbg(counter)
    {:noreply, assign(socket, counter, value - 1)}
  end
defp get_counter(counter_id, socket) do
    counter =  String.to_existing_atom(counter_id)
    {counter, socket |> Map.get(:assigns) |> Map.get(counter) }
end

  defp random_feature(), do: "real-time"
  defp transactions_count(), do: Financial.transactions_count()
  defp customers_count(), do: Customers.customers_count()
end
