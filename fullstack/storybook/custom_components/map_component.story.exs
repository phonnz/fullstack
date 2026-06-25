defmodule Storybook.CustomComponents.MapComponent do
  use PhoenixStorybook.Story, :live_component

  def component, do: FullstackWeb.Live.MapComponent

  def doc do
    "A MapLibre map component. Renders a map of Spain and allows adding countries by name."
  end

  def variations do
    [
      %Variation{
        id: :default,
        description: "Map centered on Spain with geocoding"
      }
    ]
  end
end
