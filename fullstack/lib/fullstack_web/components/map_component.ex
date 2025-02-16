defmodule FullstackWeb.Live.MapComponent do
  use FullstackWeb, :live_component
  alias MapLibre

  @fill_colour "#ffa8db"

  def render(assigns) do
    ~H"""
    <div>
      <.form for={%{}} as={:country} phx-submit="add_country" phx-target={@myself}>
        <input type="text" name="country" style="width: 50%" />
        <button type="submit" phx-target={@myself}>Add country</button>
      </.form>
      <div style="width:70%; height: 700px" id="map" phx-hook="Map" phx-update="ignore" data-id={@id} />
    </div>
    """
  end

  def update(_assigns, socket) do
    socket = assign(socket, id: socket.id)

    ml =
      MapLibre.new(center: {254.5, 25}, zoom: 4, style: :street)
      |> MapLibre.add_geocode_source("spain", "Spain", :country)
      |> MapLibre.add_layer(
        id: "spain",
        source: "spain",
        type: :fill,
        paint: [fill_color: @fill_colour, fill_opacity: 0.6]
      )
      |> MapLibre.to_spec()

    {:ok, push_event(socket, "map:#{socket.id}:init", %{"ml" => ml})}
  end

  def handle_event("add_country", %{"country" => country}, socket) do
    map =
      MapLibre.new()
      |> MapLibre.add_geocode_source(country, country, :country)
      |> MapLibre.add_layer(
        id: country,
        source: country,
        type: :fill,
        paint: [fill_color: @fill_colour, fill_opacity: 1]
      )

    source =
      Map.get(map.spec, "sources")
      |> Map.get(country)

    layer =
      Map.get(map.spec, "layers")
      |> Enum.find(fn layer -> Map.get(layer, "id") == country end)
      |> Map.put("source", source)

    {:noreply, push_event(socket, "map:#{socket.id}:add", %{"layer" => layer})}
  end
end
