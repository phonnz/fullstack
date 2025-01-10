defmodule FullstackWeb.Public.TransactionsLive.PublicTransactions do
  use FullstackWeb, :live_view

  alias Fullstack.Financial
  alias Contex.{Sparkline}
  alias Contex

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:chart_options, %{
        refresh_rate: 1000,
        number_of_points: 50,
        height: 400,
        width: 600
      })
      |> assign(:process_counts, [0])
      |> make_test_data()

    if connected?(socket) do
      Process.send_after(self(), :tick, socket.assigns.chart_options.refresh_rate)
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

  @impl true
  def handle_info(:tick, socket) do
    Process.send_after(self(), :tick, socket.assigns.chart_options.refresh_rate)

    socket =
      socket
      |> make_test_data()

    {:noreply, socket}
  end

  defp make_plot(data) do
    Sparkline.new(data)
    |> Map.update!(:height, fn _ -> 300 end)
    |> Map.update!(:width, fn _ -> 600 end)
    |> Sparkline.draw()
  end

  defp make_red_plot(data) do
    Sparkline.new(data)
    |> Sparkline.colours("#fad48e", "#ff9838")
    |> Map.update!(:height, fn _ -> 300 end)
    |> Map.update!(:width, fn _ -> 600 end)
    |> Sparkline.draw()
  end

  defp make_test_data(socket) do
    number_of_points = socket.assigns.chart_options.number_of_points

    result =
      1..number_of_points
      |> Enum.map(fn _ -> :rand.uniform(50) - 100 end)

    assign(socket, test_data: result)
  end
end
