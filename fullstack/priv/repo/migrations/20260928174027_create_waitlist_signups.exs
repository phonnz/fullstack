defmodule Fullstack.Repo.Migrations.CreateWaitlistSignups do
  use Ecto.Migration

  def change do
    create table(:waitlist_signups, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :string, null: false
      add :country, :string

      timestamps()
    end

    create unique_index(:waitlist_signups, [:email])
  end
end
