defmodule FullstackWeb.HomeLive.Urls do
  use FullstackWeb, :live_view
  alias Fullstack.Urls

  @impl true
  def mount(params, _session, socket) do
    case Urls.find_url(params["key"]) do
      {:ok, destiny} ->
        {:ok, push_navigate(socket, to: destiny)}

      {:error, :not_found} ->
        {:ok, redirect(socket, to: ~p"/urls")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <h1>redirection</h1>
    <pre>
      <%= inspect(assigns, pretty: true) %>
    </pre>

    <pre>
      defmodule  Some  do
          def code(x)   do
            x +  1
          end
        end
    </pre>
    """
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end
end
