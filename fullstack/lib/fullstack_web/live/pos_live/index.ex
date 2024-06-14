defmodule FullstackWeb.PosLive.Index do
  use FullstackWeb, :live_view

  alias Fullstack.Financial
  alias Fullstack.Financial.Pos

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :poss, Financial.list_poss())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Pos")
    |> assign(:pos, Financial.get_pos!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Pos")
    |> assign(:pos, %Pos{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Poss")
    |> assign(:pos, nil)
  end

  @impl true
  def handle_info({FullstackWeb.PosLive.FormComponent, {:saved, pos}}, socket) do
    {:noreply, stream_insert(socket, :poss, pos)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    pos = Financial.get_pos!(id)
    {:ok, _} = Financial.delete_pos(pos)

    {:noreply, stream_delete(socket, :poss, pos)}
  end
end
