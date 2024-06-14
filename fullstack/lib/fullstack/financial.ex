defmodule Fullstack.Financial do
  @moduledoc """
  The Financial context.
  """

  import Ecto.Query, warn: false
  alias Fullstack.Repo

  alias Fullstack.Financial.Pos

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
