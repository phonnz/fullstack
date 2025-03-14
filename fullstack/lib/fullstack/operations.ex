defmodule Fullstack.Operations do
  import Ecto.Query, warn: false
  alias Fullstack.Repo

  alias Fullstack.Financial.{Transaction, Transactions}
  alias Fullstack.Customers
  alias Fullstack.Customers.Customer
  alias Fullstack.Utils.Charts.ChartsDates

  defdelegate count_transactions, to: Transactions
  defdelegate count_transactions(transactions), to: Transactions

  def list_transactions(params \\ %{}) do
    Transaction
    |> limit(10)
    |> order_by(desc: :inserted_at)
    |> preload([:customer])
    |> Repo.all()
  end
end
