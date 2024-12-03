defmodule FullstackWeb.HomeLive.Urls do
  use FullstackWeb, :live_view

  @impl true
  def mount(params, _session, socket) do
    dbg(params)
    dbg(socket)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <h1>redirection</h1>
    <prev>
      <%= inspect(assigns, pretty: true) %>
    </prev>
    """
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end
end
