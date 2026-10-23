defmodule Fullstack.JidoMarketAgents.Conversations.Record do
  @moduledoc """
  Persistence schema for a market discovery conversation.

  A `Record` belongs to a `Fullstack.Accounts.User` and holds the
  aggregated validated data produced by the market validation agent,
  plus the conversation's lifecycle `status`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Fullstack.JidoMarketAgents.Conversations.Lifecycle

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(active researching analyzing building_strategy completed error)

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          user_id: Ecto.UUID.t() | nil,
          status: String.t(),
          stage: Lifecycle.stage(),
          validated_data: map() | nil,
          business_analysis: map() | nil,
          systems_strategy: map() | nil,
          tech_strategy: map() | nil
        }

  schema "jido_conversations" do
    field :title, :string
    field :status, :string, default: "active"
    field :stage, Ecto.Enum, values: Lifecycle.stages(), default: :inserted
    field :validated_data, :map
    field :business_analysis, :map
    field :systems_strategy, :map
    field :tech_strategy, :map

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
    |> cast(attrs, [
      :user_id,
      :title,
      :status,
      :validated_data,
      :business_analysis,
      :systems_strategy,
      :tech_strategy
    ])
    |> validate_required([:user_id])
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Builds a changeset that moves the record to `stage`.

  The move is validated through `Lifecycle.transition/2`. The database trigger
  is the second guard: its named check violation becomes a `:stage` error
  instead of raising.
  """
  def stage_changeset(record, stage) do
    record
    |> change(stage: stage)
    |> validate_transition(record.stage, stage)
    |> check_constraint(:stage,
      name: :jido_conversations_stage_forward_only,
      message: "cannot move backward from research onward"
    )
  end

  defp validate_transition(changeset, from, to) do
    case Lifecycle.transition(from, to) do
      :ok ->
        changeset

      {:error, _reason} ->
        add_error(changeset, :stage, "invalid transition from #{from} to #{to}")
    end
  end
end
