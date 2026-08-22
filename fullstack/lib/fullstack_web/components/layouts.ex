defmodule FullstackWeb.Layouts do
  use FullstackWeb, :html

  embed_templates "layouts/*"

  @doc """
  Classes for a LiveToast flash.

  Overrides the library default, which hardcodes `bg-white` / `text-black`
  and so renders a white card on a dark background. Mirrors the default
  structure and swaps only the colours for daisyUI alert tokens.
  """
  def toast_class_fn(assigns) do
    [
      "alert group/toast z-100 pointer-events-auto relative w-full items-center justify-between",
      "origin-center overflow-hidden rounded-lg p-4 shadow-lg col-start-1 col-end-1 row-start-1 row-end-2",
      # start hidden if javascript is enabled
      "[@media(scripting:enabled)]:opacity-0 [@media(scripting:enabled){[data-phx-main]_&}]:opacity-100",
      # used to hide the disconnected flashes
      if(assigns[:rest][:hidden] == true, do: "hidden", else: "flex"),
      assigns[:kind] == :info && "alert-info",
      assigns[:kind] == :error && "alert-error"
    ]
  end

  @doc """
  Renders the light/dark theme toggle.

  The theme itself is resolved before first paint by the inline script in
  `root.html.heex`; this component only lets the user override that choice.
  The override is written to `localStorage` and applied by setting
  `data-theme` on `<html>`, so switching never involves a LiveView
  round-trip and cannot flash the wrong theme.

  Both buttons carry an accessible name and `aria-pressed`, and the icons
  are `aria-hidden` — the name lives on the button, never on the glyph.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div
      id="theme-toggle"
      phx-update="ignore"
      role="group"
      aria-label="Colour theme"
      class="flex items-center gap-1 rounded-full border border-base-300 bg-base-200 p-1"
    >
      <button
        type="button"
        data-set-theme="light"
        aria-label="Light theme"
        class="theme-option flex h-8 w-8 items-center justify-center rounded-full focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
      >
        <.icon name="hero-sun-mini" class="h-4 w-4" aria-hidden="true" />
      </button>
      <button
        type="button"
        data-set-theme="dark"
        aria-label="Dark theme"
        class="theme-option flex h-8 w-8 items-center justify-center rounded-full focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
      >
        <.icon name="hero-moon-mini" class="h-4 w-4" aria-hidden="true" />
      </button>
    </div>
    """
  end
end
