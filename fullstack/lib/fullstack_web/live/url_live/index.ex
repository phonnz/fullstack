defmodule FullstackWeb.UrlLive.Index do
  use FullstackWeb, :live_view

  alias Fullstack.Urls
  alias Fullstack.Urls.Url

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :ulrs, Urls.list_ulrs())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Url")
    |> assign(:url, Urls.get_url!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Url")
    |> assign(:url, %Url{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Ulrs")
    |> assign(:url, nil)
  end

  @impl true
  def handle_info({FullstackWeb.UrlLive.FormComponent, {:saved, url}}, socket) do
    {:noreply, stream_insert(socket, :ulrs, url)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    url = Urls.get_url!(id)
    {:ok, _} = Urls.delete_url(url)

    {:noreply, stream_delete(socket, :ulrs, url)}
  end
end
