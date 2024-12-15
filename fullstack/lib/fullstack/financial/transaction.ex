defmodule Fullstack.Financial.Transaction do
  use Ecto.Schema
  import Ecto.Changeset
  alias Fullstack.Customers.Customer
  alias Fullstack.Financial.Pos

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "transactions" do
    field :amount, :integer, default: 0

    field :status, Ecto.Enum,
      values: [
        :inserted,
        :started,
        :on_going,
        :ended,
        :uploading,
        :failed,
        :processing,
        :inferred,
        :outstanding,
        :paid,
        :rejected,
        :cancelled
      ],
      default: :started

    belongs_to :customer, Customer
    belongs_to :pos, Pos

    timestamps()
  end

  @doc false
  def changeset(transaction, attrs) do
    transaction
    |> cast(attrs, [:amount, :customer_id, :pos_id])
    ## |> cast_assoc(:customer_id)
    ## |> cast_assoc(:pos_id)
    |> validate_required([:amount, :customer_id, :pos_id])
  end
end
