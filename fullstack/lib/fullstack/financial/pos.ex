defmodule Fullstack.Financial.Pos do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "poss" do
    field :name, :string

    timestamps()
  end

  @doc false
  def changeset(pos, attrs) do
    pos
    |> cast(attrs, [:name])
    |> validate_required([:name])
  end
end
