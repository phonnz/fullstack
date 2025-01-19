defmodule Fullstack.Financial do
  import Ecto.Query, warn: false
  alias Fullstack.Repo

  alias Fullstack.Financial.{Transaction, Transactions}
  alias Fullstack.Customers
  alias Fullstack.Customers.Customer

  defdelegate count_transactions, to: Transactions
  defdelegate count_transactions(transactions), to: Transactions

  def build_transactions_analytics(params) do
    transactions = Transactions.list_transactions(params)

    %Transactions{}
    |> Map.put(:transactions, transactions)
    |> Map.put(:transactions_count, count_transactions())
    |> Map.put(:total_amount, set_transactions_total_amount(transactions))
    |> Map.put(:last_transactions, set_latest_transactions(transactions))
    |> Map.put(:biggest_tickets, set_biggest_transactions(transactions))
    |> set_last_customers()
    |> set_top_transactions()
    |> set_top_customers()
    |> set_transactions_per_month()
    |> set_transactions_per_day()
    |> Map.drop([:transactions, :monthly_transactions, :daily_transactions])
  end

  def build_customers_analytics(params \\ %{}) do
    Customers.list_customers(%{"only" => [:id, :inserted_at]})
    |> parse_chart_data
  end

  def to_transaction(transaction) do
    Map.take(transaction, [:id, :inserted_at, :status, :amount, :customer_id])
  end

  def set_last_customers(%{last_transactions: transactions} = data) do
    customers = transactions |> Enum.map(& &1.customer_id) |> get_customers
    Map.put(data, :last_customers, customers)
  end

  def set_top_transactions(%{transactions: transactions} = data) do
    top_transactions =
      transactions
      |> Enum.sort_by(& &1.amount, :desc)
      |> Enum.take(5)
      |> Enum.map(&to_transaction/1)

    Map.put(data, :biggest_tickets, top_transactions)
  end

  def set_top_customers(%{biggest_tickets: transactions} = data) do
    top_customers =
      transactions
      |> Enum.map(& &1.customer_id)
      |> get_customers()

    Map.put(data, :top_customers, top_customers)
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

  def set_transactions_per_month(%{transactions: transactions} = data) do
    [current_year, _m, _d] = Date.utc_today() |> parse_date()

    grouped_transactions =
      transactions
      |> Enum.filter(&year_filter(&1.inserted_at, current_year))
      |> Enum.group_by(&month_year_transactions_grouper/1)

    data
    |> Map.put(:monthly_transactions, grouped_transactions)
    |> Map.put(:monthly_data, parse_chart_data(grouped_transactions))
  end

  defp parse_chart_data([%Customer{} | _] = customers) do
    customers
    |> Enum.reduce(%{}, fn c, acc ->
      acc
      |> Map.update(
        c.inserted_at
        |> NaiveDateTime.to_date()
        |> to_string()
        |> String.split("-")
        |> Enum.take(2),
        1,
        &(&1 + 1)
      )
    end)
    |> Enum.map(fn {[_, m], value} ->
      [Timex.month_name(String.to_integer(m)), value]
    end)
  end

  defp parse_chart_data(transactions) do
    transactions
    |> Enum.map(fn {k, v} ->
      {count, amount} =
        Enum.reduce(v, {0, 0}, fn trx, {count, amount} ->
          {count + 1, trx.amount + amount}
        end)

      [" #{elem(k, 1)}", count, amount / 100_000]
    end)
  end

  defp year_filter(transaction_date, current_year) do
    [y, _m, _d] = parse_date(transaction_date)
    y == current_year
  end

  defp month_year_transactions_grouper(transaction) do
    [trx_year, trx_month, _d] =
      transaction
      |> Map.fetch!(:inserted_at)
      |> parse_date()

    {trx_year, trx_month}
  end

  defp set_transactions_per_day(%{monthly_transactions: transactions} = data) do
    [current_year, current_month, _d] = Date.utc_today() |> parse_date()

    grouped_transactions =
      transactions
      |> Map.get({current_year, current_month})
      |> Enum.group_by(&day_month_transactions_grouper/1)

    data
    |> Map.put(:daily_transactions, grouped_transactions)
    |> Map.put(:daily_data, parse_chart_data(grouped_transactions))
  end

  defp day_month_transactions_grouper(transaction) do
    [_y, trx_month, trx_day] =
      transaction
      |> Map.fetch!(:inserted_at)
      |> parse_date()

    {trx_month, trx_day}
  end

  defp parse_date(date) do
    date
    |> Date.to_string()
    |> String.split("-")
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
    |> Enum.map_join("@", &("***" <> String.slice(&1, -4, 4)))
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
