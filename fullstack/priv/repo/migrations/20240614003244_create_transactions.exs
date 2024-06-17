defmodule Fullstack.Repo.Migrations.CreateTransactions do
  use Ecto.Migration

  def change do
    create table(:transactions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :amount, :integer
      add :customer_id, references(:customers, on_delete: :nothing, type: :binary_id)
      add :pos_id, references(:poss, on_delete: :nothing, type: :binary_id)

      timestamps()
    end

    create index(:transactions, [:customer_id])
    create index(:transactions, [:pos_id])
  end
end
