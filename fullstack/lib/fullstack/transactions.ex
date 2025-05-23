defmodule Fullstack.Public.Transactions do
  import Ecto.Query, warn: false
  alias Fullstack.Public.Transactions
  alias Fullstack.Repo

  alias Fullstack.Financial.Transaction

  @valid_status [
    "inserted",
    "started",
    "on_going",
    "ended",
    "uploading",
    "failed",
    "processing",
    "inferred",
    "outstanding",
    "paid",
    "rejected",
    "cancelled"
  ]

  def list_transactions(params \\ %{}) do
    Process.sleep(1_000)

    case Enum.random([true, false]) do
      true ->
        {:ok,
         %{
           transactions:
             Transaction
             |> with_status(params)
             |> filter_by(params)
             |> set_page(params)
             |> order_by(desc: :inserted_at)
             |> Repo.all()
         }}

      false ->
        {:error, "Timeout Service"}
    end
  end

  def get(id) do
    Repo.get(Transaction, id)
  end

  defp with_status(query, %{"status" => status}) when status in @valid_status do
    where(query, status: ^status)
  end

  defp with_status(query, _), do: query

  defp filter_by(query, %{"query_filter" => query_filter}) when query_filter not in ["", nil] do
    where(query, [t], ilike(t.customer_id, ^"%#{query_filter}%"))
  end

  defp filter_by(query, _q), do: query

  @offset 10
  defp set_page(query, params) do
    page = Map.get(params, "page", "1")
    offset = (String.to_integer(page) - 1) * @offset
    limit(query, @offset) |> offset(^offset)
  end
end
