defmodule Fullstack.Customers do
  @moduledoc """
  The Customers context.
  """

  import Ecto.Query, warn: false
  alias Fullstack.Repo
  alias Fullstack.Customers.Customer
  alias Fullstack.Utils.Charts.ChartsDates

  def customers_count, do: Repo.aggregate(Customer, :count, :id)

  @doc """
  Returns the list of customers.

  ## Examples

      iex> list_customers()
      [%Customer{}, ...]

  """
  def list_customers(params \\ %{}) do
    from(c in Customer)
    |> maybe_from_created_range(params)
    |> maybe_select_fields(params)
    |> Repo.all()
  end

  defp maybe_select_fields(query, %{"only" => only_fields} = _params) when is_list(only_fields) do
    select(query, ^only_fields)
  end

  defp maybe_select_fields(query, _params), do: query

  defp maybe_from_created_range(query, params) do
    date_range = Map.merge(ChartsDates.default_date_range(), params)

    where(
      query,
      [c],
      c.inserted_at >= ^date_range["from"] and c.inserted_at <= ^date_range["until"]
    )
  end

  @doc """
  Gets a single customer.

  Raises `Ecto.NoResultsError` if the Customer does not exist.

  ## Examples

      iex> get_customer!(123)
      %Customer{}

      iex> get_customer!(456)
      ** (Ecto.NoResultsError)

  """
  def get_customer!(id), do: Repo.get!(Customer, id)

  def random_customer_id do
    Repo.all(from c in Customer, select: c.id)
    |> Enum.random()
  end

  def gen() do
    new_id =
      Repo.aggregate(Customer, :count, :id) + 1

    create_customer(%{
      full_name: "user-#{new_id}",
      email: "user-#{new_id}@email.com"
    })
  end

  @doc """

  Creates a customer.
  ## Examples

      iex> create_customer(%{field: value})
      {:ok, %Customer{}}

      iex> create_customer(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_customer(attrs \\ %{}) do
    %Customer{}
    |> Customer.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a customer.

  ## Examples

      iex> update_customer(customer, %{field: new_value})
      {:ok, %Customer{}}

      iex> update_customer(customer, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_customer(%Customer{} = customer, attrs) do
    customer
    |> Customer.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a customer.

  ## Examples

      iex> delete_customer(customer)
      {:ok, %Customer{}}

      iex> delete_customer(customer)
      {:error, %Ecto.Changeset{}}

  """
  def delete_customer(%Customer{} = customer) do
    Repo.delete(customer)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking customer changes.

  ## Examples

      iex> change_customer(customer)
      %Ecto.Changeset{data: %Customer{}}

  """
  def change_customer(%Customer{} = customer, attrs \\ %{}) do
    Customer.changeset(customer, attrs)
  end
end
