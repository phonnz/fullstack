defmodule Fullstack.Customers.Customer do
  use Ecto.Schema
  import Ecto.Changeset
  alias Fullstack.Financial.Transaction

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "customers" do
    field :full_name, :string
    field :email, :string
    has_many :transactions, Transaction, on_delete: :nothing
    timestamps()
  end

  @doc false
  def changeset(customer, attrs) do
    customer
    |> cast(attrs, [:full_name, :email])
    |> validate_required([:full_name, :email])
  end
end
