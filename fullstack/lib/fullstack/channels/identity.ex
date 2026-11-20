defmodule Fullstack.Channels.Identity do
  @moduledoc """
  An external sender on a messaging channel (for example a WhatsApp number),
  the user created for it, and the conversation it is currently using.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Fullstack.Accounts.User
  alias Fullstack.JidoMarketAgents.Conversations.Record

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "channel_identities" do
    field :channel, :string
    field :external_id, :string

    belongs_to :user, User
    belongs_to :active_conversation, Record

    timestamps()
  end

  @doc false
  def create_changeset(identity, attrs) do
    identity
    |> cast(attrs, [:channel, :external_id, :user_id])
    |> validate_required([:channel, :external_id, :user_id])
    |> unique_constraint([:channel, :external_id])
    |> foreign_key_constraint(:user_id)
  end

  @doc false
  def active_conversation_changeset(identity, conversation_id) do
    identity
    |> change(active_conversation_id: conversation_id)
    |> foreign_key_constraint(:active_conversation_id)
  end
end
