defmodule Fullstack.JidoMarketAgents.Conversations.Message do
  @moduledoc """
  Persistence schema for a single message within a market discovery
  conversation.

  A `Message` belongs to a `Fullstack.JidoMarketAgents.Conversations.Record`
  and holds the message `role` and `content`. Role validity is enforced
  only at the changeset level (not as a database check constraint) so
  that invalid roles surface as ordinary Ecto changeset errors.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @roles ~w(user assistant)

  schema "jido_conversation_messages" do
    field :role, :string
    field :content, :string
    field :metadata, :map

    belongs_to :conversation, Fullstack.JidoMarketAgents.Conversations.Record

    timestamps(updated_at: false)
  end

  @doc """
  Builds a changeset for a conversation message.

  Requires `:conversation_id`, `:role` and `:content`, and validates
  that `:role` is one of #{inspect(@roles)}.
  """
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:conversation_id, :role, :content, :metadata])
    |> validate_required([:conversation_id, :role, :content])
    |> validate_inclusion(:role, @roles)
  end
end
