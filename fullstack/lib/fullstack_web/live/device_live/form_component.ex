defmodule FullstackWeb.DeviceLive.FormComponent do
  use FullstackWeb, :live_component

  alias Fullstack.Devices

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        <%= @title %>
        <:subtitle>Use this form to manage device records in your database.</:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="device-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:wlan_mac_address]} type="text" label="Wlan mac address" />
        <.input field={@form[:eth_mac_address]} type="text" label="Eth mac address" />
        <.input field={@form[:enabled]} type="checkbox" label="Enabled" />
        <:actions>
          <.button phx-disable-with="Saving...">Save Device</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{device: device} = assigns, socket) do
    changeset = Devices.change_device(device)

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"device" => device_params}, socket) do
    changeset =
      socket.assigns.device
      |> Devices.change_device(device_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"device" => device_params}, socket) do
    save_device(socket, socket.assigns.action, device_params)
  end

  defp save_device(socket, :edit, device_params) do
    case Devices.update_device(socket.assigns.device, device_params) do
      {:ok, device} ->
        notify_parent({:saved, device})

        {:noreply,
         socket
         |> put_flash(:info, "Device updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_device(socket, :new, device_params) do
    case Devices.create_device(device_params) do
      {:ok, device} ->
        notify_parent({:saved, device})

        {:noreply,
         socket
         |> put_flash(:info, "Device created successfully")
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
