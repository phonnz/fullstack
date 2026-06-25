defmodule Storybook.CustomComponents.Subheader do
  use PhoenixStorybook.Story, :component

  def function, do: &FullstackWeb.CustomComponents.subheader/1

  def variations do
    [
      %Variation{
        id: :default,
        description: "A centered subheader with an emoji subline",
        slots: [
          "<p>Welcome to the dashboard</p>",
          ~s|<:sublines :let={emoji}>\#{emoji} Enjoy your stay</:sublines>|
        ]
      },
      %Variation{
        id: :multiple_sublines,
        description: "Subheader with multiple sublines",
        slots: [
          "<h2>System Status</h2>",
          ~s|<:sublines :let={emoji}>\#{emoji} All systems operational</:sublines>|,
          ~s|<:sublines :let={emoji}>\#{emoji} Uptime: 99.9%</:sublines>|
        ]
      }
    ]
  end
end
