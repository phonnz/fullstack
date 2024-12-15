defmodule Fullstack.Repo.Migrations.AddTransactionStatus do
  use Ecto.Migration

  def change do
    execute("CREATE TYPE transaction_status AS ENUM ('inserted',
        'started',
        'on_going',
        'ended',
        'uploading',
        'failed',
        'processing',
        'inferred',
        'outstanding',
        'paid',
        'rejected',
        'cancelled');")

    alter table(:transactions) do
      add :status, :transaction_status, null: false, default: "inserted"
    end
  end
end
