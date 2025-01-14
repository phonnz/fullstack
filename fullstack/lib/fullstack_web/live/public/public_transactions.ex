defmodule FullstackWeb.Public.TransactionsLive.PublicTransactions do
  use FullstackWeb, :live_view

  alias Fullstack.Financial
  alias Contex.{BarChart, Plot, Dataset, Sparkline}
  alias Contex

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:chart_options, %{
        refresh_rate: 1000,
        number_of_points: 50
      })
      |> assign(:process_counts, [0])
      |> assign(:bar_options, %{})
      |> assign(bar_clicked: "Click a bar. Any bar", selected_bar: nil)

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
      |> make_test_data()
      |> make_data()

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

  defp make_plot(data, bar_options, selected_bar) do
    cols = ["x", "y"]

    options = [
      mapping: %{category_col: "Month", value_cols: cols},
      type: "grouped",
      data_labels: true,
      orientation: :vertical,
      phx_event_handler: "chart1_bar_clicked",
      colour_palette: :default
    ]

    dbg(data)

    Plot.new(data, BarChart, 500, 400, options)
    |> Plot.titles("title", "Subtitle")
    |> Plot.axis_labels("x-axis", "y_axis")
    |> Plot.plot_options(%{legend_setting: :legend_right})
    |> Plot.to_svg()
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

  defp random_within_range(min, max) do
    diff = max - min
    :rand.uniform() * diff + min
  end

  defp make_data(socket) do
    options = socket.assigns.bar_options
    series_cols = ["x", "y"]
    2
    categories = Enum.count(socket.assigns.info.daily_data)
    test_data = Dataset.new(socket.assigns.info.daily_data)

    options = %{
      series_columns: series_cols
    }

    assign(socket, data: test_data, bar_options: options)
  end
end
