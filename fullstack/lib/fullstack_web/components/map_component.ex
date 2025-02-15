defmodule FullstackWeb.Live.MapComponent do
  use FullstackWeb, :live_component
  alias MapLibre

  @fill_colour "#ffa8db"

  def render(assigns) do
    ~H"""
    <div style="width:100%; height: 500px" id="map" phx-hook="Map" phx-update="ignore" data-id={@id}/>
    """
  end

  def update(_assigns, socket) do
    socket = assign(socket, id: socket.id)

    ml =
      MapLibre.new(style: :street)
      |> MapLibre.add_geocode_source("poland", "Poland", :country)
      |> MapLibre.add_layer(
        id: "poland",
        source: "poland",
        type: :fill,
        paint: [fill_color: @fill_colour, fill_opacity: 1]
      )
      |> MapLibre.to_spec()

    {:ok, push_event(socket, "map:#{socket.id}:init", %{"ml" => ml})}
  end
end
