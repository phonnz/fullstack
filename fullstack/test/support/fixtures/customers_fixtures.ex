defmodule Fullstack.CustomersFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Fullstack.Customers` context.
  """

  @doc """
  Generate a customer.
  """
  def customer_fixture(attrs \\ %{}) do
    {:ok, customer} =
      attrs
      |> Enum.into(%{
        email: "some email",
        full_name: "some full_name"
      })
      |> Fullstack.Customers.create_customer()

    customer
  end
end
