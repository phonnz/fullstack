defmodule FullstackWeb.CustomComponents do
  use FullstackWeb, :html

  slot :inner_block, required: true
  slot :sublines

  def subheader(assigns) do
    assigns = assign(assigns, :emoji, ~w(💜 🧙 🔮 🥳) |> Enum.random())

    ~H"""
    <div class="text-center">
      <%= render_slot(@inner_block) %>
      <span :for={sublines <- @sublines} class="bold text-2xl">
        <%= render_slot(sublines, @emoji) %>
      </span>
    </div>
    """
  end

  attr :btn_type, :string, values: ["warning", "error"], default: "warning"
  attr :rest, :global
  slot :inner_block, required: true

  def custom_button(assigns) do
    ~H"""
    <button
      class={[
        "btn mx-2 w-full sm:w-auto",
        "focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2",
        @btn_type == "warning" && "btn-warning focus-visible:outline-warning",
        @btn_type == "error" && "btn-error focus-visible:outline-error"
      ]}
      {@rest}
    >
      <%= render_slot(@inner_block) %>
    </button>
    """
  end
end
