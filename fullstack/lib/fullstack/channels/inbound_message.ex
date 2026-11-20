defmodule Fullstack.Channels.InboundMessage do
  @moduledoc """
  A provider message id that has already been processed, kept so that a
  retried webhook delivery is acknowledged without being processed again.
  """
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "channel_inbound_messages" do
    field :channel, :string
    field :external_id, :string

    timestamps(updated_at: false)
  end
end
