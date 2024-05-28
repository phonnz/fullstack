defmodule Fullstack.DevicesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Fullstack.Devices` context.
  """

  @doc """
  Generate a device.
  """
  def device_fixture(attrs \\ %{}) do
    {:ok, device} =
      attrs
      |> Enum.into(%{
        enabled: true,
        wlan_mac_address: "some wlan_mac_address",
        eth_mac_address: "some eth_mac_address"
      })
      |> Fullstack.Devices.create_device()

    device
  end
end
