defmodule Fullstack.Financial do
  @moduledoc """
  The Financial context.
  """

  import Ecto.Query, warn: false
  alias Fullstack.Repo

  alias Fullstack.Financial.Pos
  alias Fullstack.Customers

  @doc """
  Returns the list of poss.

  ## Examples

      iex> list_poss()
      [%Pos{}, ...]

  """
  def list_poss do
    Repo.all(Pos)
  end

  @doc """
  Gets a single pos.

  Raises `Ecto.NoResultsError` if the Pos does not exist.

  ## Examples

      iex> get_pos!(123)
      %Pos{}

      iex> get_pos!(456)
      ** (Ecto.NoResultsError)

  """
  def get_pos!(id), do: Repo.get!(Pos, id)

  def random_pos_id() do
    case Repo.all(from p in Pos, select: p.id) do
      [] ->
        {:ok, pos} = create_pos(%{name: "Main central point of sales"})
        pos.id

      poss ->
        Enum.random(poss)
    end
  end

  @doc """
  Creates a pos.

  ## Examples

      iex> create_pos(%{field: value})
      {:ok, %Pos{}}

      iex> create_pos(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_pos(attrs \\ %{}) do
    %Pos{}
    |> Pos.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a pos.

  ## Examples

      iex> update_pos(pos, %{field: new_value})
      {:ok, %Pos{}}

      iex> update_pos(pos, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_pos(%Pos{} = pos, attrs) do
    pos
    |> Pos.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a pos.

  ## Examples

      iex> delete_pos(pos)
      {:ok, %Pos{}}

      iex> delete_pos(pos)
      {:error, %Ecto.Changeset{}}

  """
  def delete_pos(%Pos{} = pos) do
    Repo.delete(pos)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking pos changes.

  ## Examples

      iex> change_pos(pos)
      %Ecto.Changeset{data: %Pos{}}

  """
  def change_pos(%Pos{} = pos, attrs \\ %{}) do
    Pos.changeset(pos, attrs)
  end

  alias Fullstack.Financial.Transaction
  def transactions_count, do: Repo.aggregate(Transaction, :count, :id)

  @doc """
  Returns the list of transactions.

  ## Examples

      iex> list_transactions()
      [%Transaction{}, ...]

  """
  def list_transactions do
    Repo.all(Transaction)
  end

  def stream_trx() do
    query =
      from(t in Transaction,
        join: c in assoc(t, :customer),
        join: p in assoc(t, :pos),
        select: %{
          date: t.inserted_at,
          transaction: t.id,
          pos: p.name,
          customer: c.full_name
        },
        order_by: [desc: t.inserted_at]
      )

    ## stream =
    {:ok, transactions} =
      Repo.transaction(fn ->
        Repo.stream(query)
        |> Task.async_stream(&set_extra_data/1, timeout: 7000)
        #        |> Enum.map(&Task.await(&1))
        |> Enum.to_list()
      end)

    transactions
  end

  defp set_extra_data(trx) do
    Process.sleep(2000)
    Map.put(trx, :description, "customer #{trx.customer} made a purchase at #{trx.pos}")
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

  def trx_gen() do
    new_trx =
      %{
        customer_id: Customers.random_customer_id(),
        pos_id: random_pos_id()
      }

    %Transaction{}
    |> Transaction.changeset(new_trx)
    |> Repo.insert()
  end

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
