defmodule Fullstack.Financial.Transaction do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "transactions" do
    field :amount, :integer
    field :customer_id, :binary_id
    field :post_id, :binary_id

    timestamps()
  end

  @doc false
  def changeset(transaction, attrs) do
    transaction
    |> cast(attrs, [:amount])
    |> validate_required([:amount])
  end
end
