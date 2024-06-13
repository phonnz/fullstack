defmodule Fullstack.Repo.Migrations.CreateDevices do
  use Ecto.Migration

  def change do
    create table(:devices, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :wlan_mac_address, :string
      add :eth_mac_address, :string
      add :enabled, :boolean, default: false, null: false

      timestamps()
    end
  end
end
