defmodule Storybook.CustomComponents.Graph do
  use PhoenixStorybook.Story, :live_component

  def component, do: FullstackWeb.Live.Graph

  def doc do
    "A VegaLite line chart component. Renders fake random data and updates via a timer."
  end

  def variations do
    [
      %Variation{
        id: :default,
        description: "Default line chart with random data"
      }
    ]
  end
end
