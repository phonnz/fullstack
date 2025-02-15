defmodule FullstackWeb.Public.DevicesLive.Index do
  alias Phoenix.LiveView.AsyncResult
  use FullstackWeb, :live_view
  alias MapLibre
  alias Fullstack.Devices
  @fill_colour "#ffa8db"

  def mount(_params, _, socket) do
    {:ok,
     socket
     |> assign(:id, "visited-countries-map")
     |> assign(:devices, AsyncResult.loading())
     |> start_async(:fetch_devices, fn -> Devices.list_devices() end)}
  end

  def render(assigns) do
    ~H"""
    <h1>Devices</h1>
    <div :if={@devices.loading}>Loading devices...</div>
    <div :if={devices = @devices.ok? && @devices.result}>
      <ul>
        <li :for={device <- devices} id={device.id}>
          <%= device.id %>
        </li>
      </ul>
    </div>
    <.live_component module={FullstackWeb.Live.MapComponent} id="visited-countries-map"/>
    """
  end

  def handle_async(:fetch_devices, {:ok, fetched_devices}, socket) do
    %{devices: devices} = socket.assigns
    {:noreply, assign(socket, :devices, AsyncResult.ok(devices, fetched_devices))}
  end

  def handle_async(:fetch_devices, {:exit, reason}, socket) do
    %{devices: devices} = socket.assigns
    {:noreply, assign(socket, :devices, AsyncResult.failed(devices, {:exit, reason}))}
  end

  def update(_assigns, socket) do
    socket = assign(socket, id: socket.id)

    ml =
      MapLibre.new(style: :street)
      |> MapLibre.add_geocode_source("spain", "Spain", :country)
      |> MapLibre.add_layer(
        id: "spain",
        source: "spain",
        type: :fill,
        paint: [fill_color: @fill_colour, fill_opacity: 1]
      )
      |> MapLibre.to_spec()

    {:ok,
     push_event(socket, "map:#{socket.id}:init", %{
       "ml" => ml})
     }
  end
end
