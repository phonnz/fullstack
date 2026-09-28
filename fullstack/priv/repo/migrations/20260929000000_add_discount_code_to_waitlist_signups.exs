defmodule Fullstack.Repo.Migrations.AddDiscountCodeToWaitlistSignups do
  use Ecto.Migration

  def change do
    alter table(:waitlist_signups) do
      add :discount_code, :string
    end
  end
end
