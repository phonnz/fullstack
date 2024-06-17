defmodule Fullstack.Devices.Heartbeat do
  use Ecto.Schema
  import Ecto.Changeset
  alias Fullstack.Devices.Device
  @primary_key {:id, :binary_id, autogenerate: false, read_after_writes: true}
  @foreign_key_type :binary_id
  schema "measurements" do
    field :logdate, :date, default: Date.utc_today()
    belongs_to :device, Device
  end
end
