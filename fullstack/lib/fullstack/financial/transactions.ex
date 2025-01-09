defmodule Fullstack.Financial.Transactions do
  defstruct [
    :transactions,
    :transactions_count,
    :total_amount,
    :year_amount_avg,
    :month_amount_current_year_avg,
    :biggest_tickets,
    :top_customers,
    :last_customers
  ]

  @moduledoc """
  The Financial context
  """

  import Ecto.Query, warn: false
  alias Fullstack.Repo

  alias Fullstack.Financial.Transaction

  def count_transactions(transactions) do
    Enum.count(transactions)
  end

  def count_transactions, do: Repo.aggregate(Transaction, :count, :id)

  @doc """
  Returns the list of transactions.

  ## Examples

      iex> list_transactions()
      [%Transaction{}, ...]

  """
  def list_transactions(params) do
    Transaction
    |> order_by(desc: :inserted_at)
    |> with_date_range(params)
    |> with_status(params)
    |> with_amount_range(params)
    |> from_customer(params)
    |> from_pos(params)
    |> Repo.all()
  end

  defp with_date_range(query, %{"dates" => %{"from" => from, "upto" => upto}}) do
    query
  end

  defp with_date_range(query, _params), do: query

  defp with_status(query, %{"status" => status}) do
    where(query, status: ^status)
  end

  defp with_status(query, _params), do: query

  defp with_amount_range(query, %{"amount_range" => %{"from" => from, "upto" => upto}}) do
    where(query, [t], t.amount >= ^from and t.amount <= ^upto)
  end

  defp with_amount_range(query, _params), do: query

  defp from_customer(query, %{"customer_id" => customer_id}) do
    where(query, [t], t.customer_id == ^customer_id)
  end

  defp from_customer(query, _params), do: query

  defp from_pos(query, %{"pos_id" => pos_id}) do
    where(query, [t], t.pos_id == ^pos_id)
  end

  defp from_pos(query, _params), do: query

  @doc """
  Returns the list of transactions.

  ## Examples

      iex> list_transactions()
      [%Transaction{}, ...]

  """
  def list_transactions do
    Repo.all(Transaction)
  end

  @doc """
  Gets a single transaction.

  Raises `Ecto.NoResultsError` if the Transaction does not exist.

  ## Examples

      iex> get_transaction!(123)
      %Transaction{}

      iex> get_transaction!(456)
      ** (Ecto.NoResultsError)

  """
  def get_transaction!(id), do: Repo.get!(Transaction, id)

  @doc """
  Creates a transaction.

  ## Examples

      iex> create_transaction(%{field: value})
      {:ok, %Transaction{}}

      iex> create_transaction(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_transaction(attrs \\ %{}) do
    %Transaction{}
    |> Transaction.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a transaction.

  ## Examples

      iex> update_transaction(transaction, %{field: new_value})
      {:ok, %Transaction{}}

      iex> update_transaction(transaction, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_transaction(%Transaction{} = transaction, attrs) do
    transaction
    |> Transaction.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a transaction.

  ## Examples

      iex> delete_transaction(transaction)
      {:ok, %Transaction{}}

      iex> delete_transaction(transaction)
      {:error, %Ecto.Changeset{}}

  """
  def delete_transaction(%Transaction{} = transaction) do
    Repo.delete(transaction)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking transaction changes.

  ## Examples

      iex> change_transaction(transaction)
      %Ecto.Changeset{data: %Transaction{}}

  """
  def change_transaction(%Transaction{} = transaction, attrs \\ %{}) do
    Transaction.changeset(transaction, attrs)
  end
end
