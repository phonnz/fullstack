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
  The site header: brand on the left, account controls on the right, one row.

  A container around `brand/1` and `account_nav/1` so the two halves stay
  independently editable. Lives in the `app` and `devices` layouts rather
  than `root`, so it renders inside the LiveView and can react to
  `@current_user`.
  """
  attr :current_user, :any, default: nil

  def site_header(assigns) do
    ~H"""
    <header class="border-b border-base-300">
      <div class="flex h-14 items-center justify-between gap-4 px-4 sm:px-6 lg:px-8">
        <.brand />
        <.account_nav current_user={@current_user} />
      </div>
    </header>
    """
  end

  @doc """
  Left half of the site header: logo and the Phoenix version badge.

  The logo carries the accessible name; the `<img>` is decorative and
  intentionally has an empty `alt`, so the link is announced once rather
  than twice.
  """
  def brand(assigns) do
    ~H"""
    <div class="flex min-w-0 items-center gap-3">
      <a
        href="/"
        aria-label="Fullstack home"
        class="-my-2 flex h-11 w-11 flex-none items-center justify-center rounded-md focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
      >
        <img src={~p"/img/logo.svg"} width="28" height="28" alt="" />
      </a>
      <p class="badge badge-outline badge-sm hidden text-brand-content border-brand-content/40 font-medium sm:inline-flex">
        v{Application.spec(:phoenix, :vsn)}
      </p>
    </div>
    """
  end

  @doc """
  Right half of the site header: theme toggle and account links.

  The `<nav>` carries `aria-label="Account"` — it is the app's only
  navigation landmark.
  """
  attr :current_user, :any, default: nil

  def account_nav(assigns) do
    ~H"""
    <nav aria-label="Account" class="flex flex-none items-center gap-2 sm:gap-3">
      <.theme_toggle />
      <ul class="flex items-center gap-2 text-[0.8125rem] leading-6 sm:gap-3">
        <%= if @current_user do %>
          <li class="hidden max-w-[16rem] truncate text-muted lg:block">
            {@current_user.email}
          </li>
          <li>
            <.link href={~p"/users/settings"} class={nav_link_class()}>Settings</.link>
          </li>
          <li>
            <.link href={~p"/users/log_out"} method="delete" class={nav_link_class()}>
              Log out
            </.link>
          </li>
        <% else %>
          <li>
            <.link href={~p"/users/register"} class={nav_link_class()}>Register</.link>
          </li>
          <li>
            <.link href={~p"/users/log_in"} class={nav_link_class()}>Log in</.link>
          </li>
        <% end %>
      </ul>
    </nav>
    """
  end

  defp nav_link_class do
    "-my-2 inline-flex min-h-[2.75rem] items-center rounded-sm px-2 font-semibold hover:text-primary " <>
      "focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 " <>
      "focus-visible:outline-primary"
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
        class="theme-option relative flex h-8 w-8 items-center justify-center rounded-full before:absolute before:left-1/2 before:top-1/2 before:h-11 before:w-11 before:-translate-x-1/2 before:-translate-y-1/2 before:content-[''] focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
      >
        <.icon name="hero-sun-mini" class="h-4 w-4" aria-hidden="true" />
      </button>
      <button
        type="button"
        data-set-theme="dark"
        aria-label="Dark theme"
        class="theme-option relative flex h-8 w-8 items-center justify-center rounded-full before:absolute before:left-1/2 before:top-1/2 before:h-11 before:w-11 before:-translate-x-1/2 before:-translate-y-1/2 before:content-[''] focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
      >
        <.icon name="hero-moon-mini" class="h-4 w-4" aria-hidden="true" />
      </button>
    </div>
    """
  end
end
