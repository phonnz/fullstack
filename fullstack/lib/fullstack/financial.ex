defmodule Fullstack.Financial do
  import Ecto.Query, warn: false
  alias Fullstack.Repo

  alias Fullstack.Financial.{Transaction, Transactions}
  alias Fullstack.Customers
  alias Fullstack.Customers.Customer

  #  defdelegate transactions_count(), to: Transactions.transactions_count()

  def build_transactions_analytics do
    transactions = Transactions.list_transactions(%{})

    %Transactions{}
    |> Map.put(:transactions, transactions)
    |> Map.put(:transactions_count, Enum.count(transactions))
    |> Map.put(:total_amount, set_transactions_total_amount(transactions))
    |> Map.put(:last_transactions, set_latest_transactions(transactions))
    |> Map.put(:biggest_tickets, set_biggest_transactions(transactions))
    |> set_last_customers()
    |> set_top_transactions()
  end

  def to_transaction(transaction) do
    transaction
    |> Map.take([:id, :inserted_at, :status, :amount, :customer_id])
  end

  def set_last_customers(%{last_transactions: transactions} = data) do
    customers = transactions |> Enum.map(& &1.customer_id) |> get_customers
    Map.put(data, :last_customers, customers)
  end

  def set_top_transactions(%{transactions: transactions} = data) do
    top_transactions =
      transactions
      |> Enum.sort_by( fn %{amount: x}, %{amount: y} -> :lt == Date.compare(x, y) end)desc: :amount)
      |> Enum.take(5)

    Map.put(data, :biggest_tickets, top_transactions)
  end

  def set_transactions_count(transactions) do
    {:ok, task_transaction} =
      Task.start(
        Transactions,
        :count_transactions,
        transactions: transactions
      )

    task_transaction
  end

  def set_transactions_total_amount(transactions) do
    Enum.reduce(transactions, 0, fn trx, acc -> trx.amount + acc end)
  end

  def set_biggest_transactions(transactions) do
    transactions
    |> Enum.sort_by(& &1.amount, :desc)
    |> Enum.take(5)
    |> Enum.map(&to_transaction/1)
  end

  defp set_latest_transactions(transactions) do
    Enum.take(transactions, 5)
    |> Enum.map(&to_transaction/1)
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

  def trx_gen() do
    new_trx =
      %{
        customer_id: Customers.random_customer_id(),
        pos_id: random_pos_id(),
        amount: Enum.random(100..10_000)
      }

    %Transaction{}
    |> Transaction.changeset(new_trx)
    |> Repo.insert()
    |> broadcast_transaction()
  end

  defp broadcast_transaction({:ok, transaction} = result) do
    FullstackWeb.Endpoint.broadcast("transactions", "new_transaction", transaction)
    result
  end

  ## customers
  def get_customers(customer_ids) when is_list(customer_ids) do
    Customer
    |> where([c], c.id in ^customer_ids)
    |> select([c], c.email)
    |> Repo.all()
    |> Enum.map(&to_customer/1)
  end

  defp to_customer(customer_email) when is_binary(customer_email) do
    customer_email
    |> String.split("@")
    |> Enum.map_join(&("***" <> String.slice(&1, -4, 4)))
  end

  ## POS
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
end
