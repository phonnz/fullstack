defmodule FullstackWeb.Public.TransactionsLive.PublicTransactions do
  use FullstackWeb, :live_view

  alias Fullstack.Devices
  alias Fullstack.Financial
  alias Contex.{BarChart, Plot, Dataset, Sparkline, LinePlot}
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
      |> assign(:customers, Financial.build_customers_analytics(params))
      |> assign(:devices, Devices.list_devices())
      |> assign(:form, to_form(params))
      |> make_test_data()
      |> assign(
        bar_options: [
          type: :grouped,
          orientation: :vertical,
          show_data_labels: "yes",
          show_selected: "no",
          show_axislabels: "no",
          custom_value_scale: "no",
          title: nil,
          subtitle: nil,
          colour_scheme: "themed",
          legend_setting: "legend_none",
          mapping: %{category_col: "Category", value_cols: ["Series 1", "Series 2", "Series 3"]},
          type: :grouped,
          data_labels: true,
          orientation: :vertical,
          phx_event_handler: "chart1_bar_clicked",
          colour_palette: :default
        ]
      )
      |> assign(bar_clicked: "Click a bar. Any bar", selected_bar: nil)
      |> assign(prev_series: 0, prev_points: 0, prev_time_series: nil)
      |> make_point_data

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
    series_cols = ["customers"]
    test_data = Dataset.new(data, ["Month" | series_cols])

    options = [
      type: :grouped,
      orientation: :vertical,
      show_data_labels: "yes",
      show_selected: "no",
      show_axislabels: "yes",
      # custom_value_scale: "no",
      title: "New Customers",
      subtitle: "Per Month",
      colour_scheme: :default,
      legend_setting: :legend_right,
      mapping: %{category_col: "Month", value_cols: series_cols},
      data_labels: true,
      phx_event_handler: "chart1_bar_clicked",
      colour_palette: :default
    ]

    Plot.new(test_data, BarChart, 500, 400, options)
    |> Plot.axis_labels("Month", "New Customers")
    |> Plot.to_svg()
  end

  defp make_point_plot(data, bar_options, selected_bar) do
    series_cols = ["Count", "Amount"]
    test_data = Dataset.new(data, ["Day" | series_cols])

    options = [
      type: :line,
      orientation: :vertical,
      show_data_labels: "yes",
      show_selected: "no",
      show_axislabels: "yes",
      # custom_value_scale: "no",
      title: "Sales",
      subtitle: "Month",
      colour_scheme: :default,
      legend_setting: :legend_right,
      mapping: %{category_col: "Day", value_cols: series_cols},
      data_labels: true,
      phx_event_handler: "chart1_bar_clicked",
      colour_palette: :default
    ]

    Plot.new(test_data, PointPlot, 500, 400, options)
    |> Plot.axis_labels("Day", "Count / Amount")
    |> Plot.to_svg()
  end

  defp make_red_plot(data) do
    Sparkline.new(data)
    |> Sparkline.colours("#fad48e", "#ff9838")
    |> Map.update!(:height, fn _ -> 60 end)
    |> Map.update!(:width, fn _ -> 150 end)
    |> Sparkline.draw()
  end

  defp make_test_data(socket) do
    number_of_points = socket.assigns.chart_options.number_of_points

    result =
      1..number_of_points
      |> Enum.map(fn _ -> :rand.uniform(50) - 100 end)

    assign(socket, test_data: result)
  end

  def format_trx_period(value) when value <= 0.0, do: ""

  def format_trx_period(value) do
    value
    |> round()
    |> Timex.month_name()
  end

  def build_pointplot(dataset, chart_options) do
    module =
      case chart_options.type do
        "line" -> LinePlot
        _ -> PointPlot
      end

    # custom_x_scale = make_custom_x_scale(chart_options)
    # custom_y_scale = make_custom_y_scale(chart_options)

    options = [
      mapping: %{x_col: "X", y_cols: chart_options.series_columns},
      colour_palette: :defatult,
      #    custom_x_scale: custom_x_scale,
      # custom_y_scale: custom_y_scale,
      custom_x_formatter: &format_trx_period/1,
      #  custom_y_formatter: y_tick_formatter,
      smoothed: chart_options.smoothed == "yes"
    ]

    plot_options =
      case chart_options.legend_setting do
        "legend_right" -> %{legend_setting: :legend_right}
        "legend_top" -> %{legend_setting: :legend_top}
        "legend_bottom" -> %{legend_setting: :legend_bottom}
        _ -> %{}
      end

    plot =
      Plot.new(dataset, module, 600, 400, options)
      |> Plot.titles(chart_options.title, nil)
      |> Plot.plot_options(plot_options)

    Plot.to_svg(plot)
  end

  @date_min ~N{2019-10-01 10:00:00}
  @interval_seconds 600
  defp calc_x(x, _, false), do: x

  defp calc_x(_, i, _) do
    NaiveDateTime.add(@date_min, i * @interval_seconds)
  end

  defp make_point_data(socket) do
    options =
      %{
        series: 2,
        points: 12,
        title: "Sales / Transactions",
        type: "line",
        smoothed: "yes",
        colour_scheme: "default",
        legend_setting: "legend_right",
        custom_x_scale: "yes",
        custom_y_scale: "no",
        custom_y_ticks: "no",
        time_series: "yes"
      }

    time_series = options.time_series == "yes"
    prev_series = socket.assigns.prev_series
    prev_points = socket.assigns.prev_points
    prev_time_series = socket.assigns.prev_time_series
    series = options.series
    points = options.points

    needs_update =
      prev_series != series or prev_points != points or prev_time_series != time_series

    data =
      for i <- 1..points do
        x = i * 5 + random_within_range(0.0, 3.0)

        series_data =
          for s <- 1..series do
            s * 8.0 + random_within_range(x * (0.1 * s), x * (0.35 * s))
          end

        [i | series_data]
        ##        [calc_x(x, i, time_series) | series_data]
      end

    dbg(data)

    series_cols =
      for s <- 1..series do
        "Series #{s}"
      end

    dbg(series_cols)

    test_data =
      case needs_update do
        true -> Dataset.new(data, ["X" | series_cols])
        _ -> socket.assigns.test_data
      end

    options = Map.put(options, :series_columns, series_cols)

    assign(socket,
      point_data: test_data,
      point_options: options,
      prev_series: series,
      prev_points: points,
      prev_time_series: time_series
    )
  end

  defp random_within_range(min, max) do
    diff = max - min
    :rand.uniform() * diff + min
  end
end
