defmodule Fullstack.Repo.Migrations.CreateCustomers do
  use Ecto.Migration

  def change do
    create table(:customers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :full_name, :string
      add :email, :string

      timestamps()
    end
  end
end
