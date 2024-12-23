defmodule FullstackWeb.DeviceLive.Index do
  use FullstackWeb, :live_view

  alias Fullstack.Devices
  alias Fullstack.Devices.Device

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      # |> assign(:char_data, [])
      |> stream(:devices, Devices.list_devices())
      |> assign(:form, to_form(%{}))

    ##    socket =
    ##      socket
    ##      |> attach_hook(:devices, :after_render, fn ->
    ##        IO.inspect(socket.assigns.devices, label: :devices_after)
    ##      end)

    {:ok, socket, layout: {FullstackWeb.Layouts, :devices}}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Device")
    |> assign(:device, Devices.get_device!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Device")
    |> assign(:device, %Device{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Devices")
    |> assign(:device, nil)
  end

  @impl true
  def handle_info({FullstackWeb.DeviceLive.FormComponent, {:saved, device}}, socket) do
    {:noreply, stream_insert(socket, :devices, device)}
  end

  @impl true
  def handle_info(:clock_tick, socket) do
    today = Date.utc_today() |> Date.add(10)
    x = %{total: 88, date: Date.to_iso8601(today), name: "potato"}

    {:noreply, update(socket, :chart_data, [x | socket.assigns.char_data])}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    device = Devices.get_device!(id)
    {:ok, _} = Devices.delete_device(device)

    {:noreply, stream_delete(socket, :devices, device)}
  end
end
