defmodule Fullstack.Operations do
  @moduledoc false
  import Ecto.Query, warn: false
  alias Fullstack.Repo

  alias Fullstack.Financial.{Transaction, Transactions}

  defdelegate count_transactions, to: Transactions
  defdelegate count_transactions(transactions), to: Transactions

  def list_transactions(_params \\ %{}) do
    Transaction
    |> limit(10)
    |> order_by(desc: :inserted_at)
    |> preload([:customer])
    |> Repo.all()
  end
end
