defmodule Storybook.CustomComponents.CustomButton do
  use PhoenixStorybook.Story, :component

  def function, do: &FullstackWeb.CustomComponents.custom_button/1

  def attributes do
    [
      %Attr{
        id: :btn_type,
        type: :string,
        default: "warning",
        values: ["warning", "error"],
        doc: "Button style variant"
      }
    ]
  end

  def variations do
    [
      %Variation{
        id: :warning,
        description: "Warning button (orange)",
        attributes: %{btn_type: "warning"},
        slots: ["<span>Warning Action</span>"]
      },
      %Variation{
        id: :error,
        description: "Error/danger button (red)",
        attributes: %{btn_type: "error"},
        slots: ["<span>Delete Item</span>"]
      },
      %VariationGroup{
        id: :all_variants,
        description: "All button variants side by side",
        variations: [
          %Variation{
            id: :warning_long,
            attributes: %{btn_type: "warning"},
            slots: ["Save Changes"]
          },
          %Variation{
            id: :error_long,
            attributes: %{btn_type: "error"},
            slots: ["Discard Changes"]
          }
        ]
      }
    ]
  end
end
