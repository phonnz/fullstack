defmodule Fullstack.Waitlist.Signup do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "waitlist_signups" do
    field :email, :string
    field :country, :string

    timestamps()
  end

  @doc false
  def changeset(signup, attrs) do
    signup
    |> cast(attrs, [:email, :country])
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> validate_length(:email, max: 160)
    |> unsafe_validate_unique(:email, Fullstack.Repo)
    |> unique_constraint(:email)
  end
end
