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
      |> make_transactions_data()

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
    dbg(data)

    options = [
      type: :grouped,
      orientation: :vertical,
      show_data_labels: "yes",
      show_selected: "no",
      show_axislabels: "yes",
      custom_value_scale: "no",
      title: "Sales",
      subtitle: "Month",
      colour_scheme: :default,
      legend_setting: :legend_right,
      mapping: %{category_col: "Category", value_cols: ["Series 1", "Series 2", "Series 3"]},
      data_labels: true,
      phx_event_handler: "chart1_bar_clicked",
      colour_palette: :default
    ]

    Plot.new(data, BarChart, 500, 400, options)
    |> Plot.axis_labels("Day", "Count / Amount")
    |> Plot.to_svg()
  end

  defp make_transactions_data(socket) do
    options = Map.new(socket.assigns.bar_options)
    # options.series
    series = 3
    # options.categories
    categories = 10

    data =
      1..categories
      |> Enum.map(fn cat ->
        series_data =
          for _ <- 1..series do
            random_within_range(10.0, 100.0)
          end

        ["Category #{cat}" | series_data]
      end)

    series_cols =
      for i <- 1..series do
        "Series #{i}"
      end

    test_data = Dataset.new(data, ["Category" | series_cols])

    options = Map.put(options, :series_columns, series_cols)

    assign(socket, data: test_data, bar_options: options)
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
end
