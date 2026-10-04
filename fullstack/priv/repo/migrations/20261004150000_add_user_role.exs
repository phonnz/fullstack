defmodule Fullstack.Repo.Migrations.AddUserRole do
  use Ecto.Migration

  def change do
    # Native enum type, mirroring the `transaction_status` pattern. Unlike
    # that migration, the down direction drops the type so a rollback does
    # not leave an orphaned type behind.
    execute(
      "CREATE TYPE user_role AS ENUM ('user', 'staff', 'admin');",
      "DROP TYPE user_role;"
    )

    alter table(:users) do
      add :role, :user_role, null: false, default: "user"
    end

    create index(:users, [:role])
  end
end
