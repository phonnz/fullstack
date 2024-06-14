defmodule FullstackWeb.PosLive.FormComponent do
  use FullstackWeb, :live_component

  alias Fullstack.Financial

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        <%= @title %>
        <:subtitle>Use this form to manage pos records in your database.</:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="pos-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:name]} type="text" label="Name" />
        <:actions>
          <.button phx-disable-with="Saving...">Save Pos</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{pos: pos} = assigns, socket) do
    changeset = Financial.change_pos(pos)

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"pos" => pos_params}, socket) do
    changeset =
      socket.assigns.pos
      |> Financial.change_pos(pos_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"pos" => pos_params}, socket) do
    save_pos(socket, socket.assigns.action, pos_params)
  end

  defp save_pos(socket, :edit, pos_params) do
    case Financial.update_pos(socket.assigns.pos, pos_params) do
      {:ok, pos} ->
        notify_parent({:saved, pos})

        {:noreply,
         socket
         |> put_flash(:info, "Pos updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_pos(socket, :new, pos_params) do
    case Financial.create_pos(pos_params) do
      {:ok, pos} ->
        notify_parent({:saved, pos})

        {:noreply,
         socket
         |> put_flash(:info, "Pos created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
