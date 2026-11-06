defmodule Fullstack.Financial.TransactionsTest do
  use Fullstack.DataCase

  import Ecto.Query

  import Fullstack.FinancialFixtures

  alias Fullstack.Financial.Transaction
  alias Fullstack.Financial.Transactions
  alias Fullstack.Repo

  defp transaction_at(%DateTime{} = inserted_at) do
    transaction = transaction_fixture()

    Repo.update_all(from(t in Transaction, where: t.id == ^transaction.id),
      set: [inserted_at: inserted_at]
    )

    transaction.id
  end

  describe "list_transactions/1 date range" do
    test "returns only transactions inside the given dates" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      inside = transaction_at(DateTime.add(now, -2, :day))
      _outside = transaction_at(DateTime.add(now, -30, :day))

      params = %{
        "dates" => %{
          "from" => DateTime.add(now, -5, :day),
          "until" => now
        }
      }

      assert [%{id: ^inside}] = Transactions.list_transactions(params)
    end

    test "returns every transaction when no dates are given" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      ids = [
        transaction_at(DateTime.add(now, -2, :day)),
        transaction_at(DateTime.add(now, -30, :day))
      ]

      assert ids |> Enum.sort() ==
               %{} |> Transactions.list_transactions() |> Enum.map(& &1.id) |> Enum.sort()
    end
  end
end
