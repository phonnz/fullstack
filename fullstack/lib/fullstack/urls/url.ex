defmodule Fullstack.Urls.Url do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "urls" do
    field :origin, :string
    field :destiny, :string
    field :visit_count, :integer, default: 0

    timestamps()
  end

  @doc false
  def changeset(url, attrs) do
    url
    |> cast(attrs, [:origin, :destiny, :visit_count])
    |> validate_required([:origin, :destiny])
    |> validate_format(:destiny, ~r/^(http)(s)?(:\/\/)(www\.)?[a-zA-Z0-9-]+(\.[a-zA-Z]{2,})+$/)
  end
end
