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

  def custom_button(assigns) do
    ~H"""
    <button
      class={[
        "inline-flex items-center text-white justify-center rounded-md text-sm font-medium ring-offset-background transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:pointer-events-none disabled:opacity-50 text-primary-foreground hover:bg-primary/90 h-10 mx-2 px-4 py-2 w-full sm:w-auto",
        @btn_type == "warning" && "bg-orange-500",
        @btn_type == "error" && "hover:ring-red-900 bg-red-700 hover:bg-red-600"
      ]}
      {@rest}
    >
      <%= render_slot(@inner_block) %>
    </button>
    """
  end
end
