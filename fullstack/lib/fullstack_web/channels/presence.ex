defmodule FullstackWeb.Presence do
  @moduledoc """
  Provides presence tracking to channels and processes.

  See the [`Phoenix.Presence`](https://hexdocs.pm/phoenix/Phoenix.Presence.html)
  docs for more details.
  """

  use Phoenix.Presence,
    otp_app: :fullstack,
    pubsub_server: Fullstack.PubSub

  def init(_opts) do
    {:ok, %{}}
  end

  def fetch(_topic, presences) do
    for {key, %{metas: [meta | metas]}} <- presences, into: %{} do
      # user can be populated here from the database here we populate
      # the name for demonstration purposes
      {key, %{metas: [meta | metas], mac_addr: meta.mac_addr, device: %{mac_addr: meta.mac_addr}}}
    end
  end

  def handle_metas(topic, %{joins: joins, leaves: leaves}, presences, state) do
    for {device_id, presence} <- joins do
      device_data = %{
        mac_addr: device_id,
        device: presence.device,
        metas: Map.fetch!(presences, device_id)
      }

      msg = {__MODULE__, {:join, device_data}}
      Phoenix.PubSub.local_broadcast(Fullstack.PubSub, "proxy:#{topic}", msg)
    end

    for {device_id, presence} <- leaves do
      metas =
        case Map.fetch(presences, device_id) do
          {:ok, presence_metas} -> presence_metas
          :error -> []
        end

      device_data = %{mac_addr: device_id, device: presence.device, metas: metas}
      msg = {__MODULE__, {:leave, device_data}}
      Phoenix.PubSub.local_broadcast(Fullstack.PubSub, "proxy:#{topic}", msg)
    end

    {:ok, state}
  end
end
