defmodule Fullstack.JidoMarketAgents.Conversations.Record do
  @moduledoc """
  Persistence schema for a market discovery conversation.

  A `Record` belongs to a `Fullstack.Accounts.User` and holds the
  aggregated validated data produced by the market validation agent,
  plus the conversation's lifecycle `status`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(active researching analyzing building_strategy completed error)

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          user_id: Ecto.UUID.t() | nil,
          status: String.t(),
          validated_data: map() | nil
        }

  schema "jido_conversations" do
    field :title, :string
    field :status, :string, default: "active"
    field :validated_data, :map

    # Populated only by `Conversations.list_all/1`, which aggregates the
    # count in the same query instead of preloading messages per row.
    field :message_count, :integer, virtual: true

    belongs_to :user, Fullstack.Accounts.User

    has_many :messages, Fullstack.JidoMarketAgents.Conversations.Message,
      foreign_key: :conversation_id

    timestamps()
  end

  @doc """
  Builds a changeset for a conversation record.

  Requires `:user_id` and validates that `:status`, when present, is one
  of #{inspect(@statuses)}.
  """
  def changeset(record, attrs) do
    record
    |> cast(attrs, [:user_id, :title, :status, :validated_data])
    |> validate_required([:user_id])
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:user_id)
  end
end
