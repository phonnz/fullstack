defmodule Fullstack.Devices.Device do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "devices" do
    field :enabled, :boolean, default: false
    field :wlan_mac_address, :string
    field :eth_mac_address, :string

    timestamps()
  end

  @doc false
  def changeset(device, attrs) do
    device
    |> cast(attrs, [:wlan_mac_address, :eth_mac_address, :enabled])
    |> validate_required([:wlan_mac_address, :eth_mac_address, :enabled])
  end
end
