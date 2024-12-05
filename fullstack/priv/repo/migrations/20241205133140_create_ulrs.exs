defmodule Fullstack.Repo.Migrations.CreateUlrs do
  use Ecto.Migration

  def change do
    create table(:urls, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :origin, :string
      add :destiny, :string
      add :visit_count, :integer

      timestamps()
    end
  end
end
