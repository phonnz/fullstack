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

    # Backfill configured bootstrap admins that already exist. Inlined as SQL
    # rather than calling Accounts.promote_bootstrap_admins/0, so this
    # migration keeps working if that function is later changed or removed.
    # A no-op when nothing is configured or no matching user exists.
    emails =
      :fullstack
      |> Application.get_env(:bootstrap_admin_emails, [])
      |> Enum.map(&(&1 |> to_string() |> String.trim() |> String.downcase()))
      |> Enum.reject(&(&1 == ""))

    if emails != [] do
      list = Enum.map_join(emails, ", ", &"'#{String.replace(&1, "'", "''")}'")

      execute(
        "UPDATE users SET role = 'admin' WHERE lower(email::text) IN (#{list});",
        "UPDATE users SET role = 'user' WHERE lower(email::text) IN (#{list});"
      )
    end
  end
end
