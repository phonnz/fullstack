# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Fullstack.Repo.insert!(%Fullstack.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

# Grant the :admin role to every configured bootstrap admin that already
# exists. Idempotent and safe to re-run.
#
# The add_user_role migration performs the same backfill, but only sees the
# configuration present when it ran — an environment that migrated before
# :bootstrap_admin_emails was set would otherwise never promote anyone.
{promoted, _} = Fullstack.Accounts.promote_bootstrap_admins()
IO.puts("Bootstrap admins promoted: #{promoted}")
