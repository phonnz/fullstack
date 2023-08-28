defmodule Fullstack.Repo do
  use Ecto.Repo,
    otp_app: :fullstack,
    adapter: Ecto.Adapters.Postgres
end
