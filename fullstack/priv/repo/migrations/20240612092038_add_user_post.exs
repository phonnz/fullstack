defmodule Fullstack.Repo.Migrations.AddUserPost do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      add :author_id, references(:users, on_delete: :nothing, type: :binary_id)
    end

    create index(:posts, [:author_id])
  end
end
