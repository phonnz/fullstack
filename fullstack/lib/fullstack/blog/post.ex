defmodule Fullstack.Blog.Post do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "posts" do
    field :title, :string
    field :content, :string
    belongs_to :author, Fullstack.Accounts.User
    timestamps()
  end

  @doc false
  def changeset(post, attrs) do
    post
    |> cast(attrs, [:title, :content, :author_id])
    |> validate_required([:title, :content, :author_id])
    |> assoc_constraint(:author)
  end
end
