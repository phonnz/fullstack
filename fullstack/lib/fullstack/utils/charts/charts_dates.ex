defmodule Fullstack.Utils.Charts.ChartsDates do
  def parse_chart_data([%Fullstack.Customers.Customer{} | _] = customers) do
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

  def parse_chart_data(transactions) do
    transactions
    |> Enum.reduce(%{}, fn trx, acc ->
      key =
        trx.inserted_at
        |> NaiveDateTime.to_date()
        |> to_string()
        |> String.split("-")
        |> Enum.take(2)

      values =
        acc
        |> Map.get(key, %{})
        |> Map.update(:count, 1, &(&1 + 1))
        |> Map.update(:amount, 0.0, &(&1 + trx.amount))

      Map.put(acc, key, values)
    end)
    |> Enum.map(fn {[y, m], %{count: count, amount: amount}} ->
      month = if y == "2025", do: String.to_integer(m) + 12, else: String.to_integer(m)

      [
        month,
        count,
        Float.ceil(amount / 10_000, 2)
      ]
    end)
  end

  def default_date_range() do
    until = DateTime.utc_now()
    from = Timex.shift(until, years: -1)
    %{"from" => from, "until" => until}
  end

  def year_filter(transaction_date, current_year) do
    [y, _m, _d] = parse_date(transaction_date)
    y == current_year
  end

  def month_year_transactions_grouper(transaction) do
    [trx_year, trx_month, _d] =
      transaction
      |> Map.fetch!(:inserted_at)
      |> parse_date()

    {trx_year, trx_month}
  end

  def day_month_transactions_grouper(transaction) do
    [_y, trx_month, trx_day] =
      transaction
      |> Map.fetch!(:inserted_at)
      |> parse_date()

    {trx_month, trx_day}
  end

  def parse_date(date) do
    date
    |> Date.to_string()
    |> String.split("-")
  end
end
