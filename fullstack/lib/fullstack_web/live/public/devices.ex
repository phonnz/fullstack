defmodule FullstackWeb.Public.DevicesLive.Index do
  alias Phoenix.LiveView.AsyncResult
  use Phoenix.LiveView
  alias Fullstack.Devices

  def mount(_params, _, socket) do
    {:ok,
     socket
     |> assign(:devices, AsyncResult.loading())
     |> start_async(:fetch_devices, fn -> Devices.list_devices() end)}
  end

  def render(assigns) do
    ~H"""
    <h1>Devices</h1>
    <div :if={@devices.loading}>Loading devices...</div>
    <div :if={devices = @devices.ok? && @devices.result}>
      <ul>
        <li :for={device <- devices} id={device.id}>
          <%= device.id %>
        </li>
      </ul>
    </div>
    """
  end

  def handle_async(:fetch_devices, {:ok, fetched_devices}, socket) do
    dbg()
    %{devices: devices} = socket.assigns
    {:noreply, assign(socket, :devices, AsyncResult.ok(devices, fetched_devices))}
  end

  def handle_async(:fetch_devices, {:exit, reason}, socket) do
    %{devices: devices} = socket.assigns
    {:noreply, assign(socket, :devices, AsyncResult.failed(devices, {:exit, reason}))}
  end
end
