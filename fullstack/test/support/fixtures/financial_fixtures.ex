defmodule Fullstack.FinancialFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Fullstack.Financial` context.
  """

  @doc """
  Generate a pos.
  """
  def pos_fixture(attrs \\ %{}) do
    {:ok, pos} =
      attrs
      |> Enum.into(%{
        name: "some name"
      })
      |> Fullstack.Financial.create_pos()

    pos
  end

  @doc """
  Generate a transaction.
  """
  def transaction_fixture(attrs \\ %{}) do
    customer = Fullstack.CustomersFixtures.customer_fixture()
    pos = pos_fixture()

    {:ok, transaction} =
      attrs
      |> Enum.into(%{
        amount: 42,
        customer_id: customer.id,
        pos_id: pos.id
      })
      |> Fullstack.Financial.create_transaction()

    transaction
  end
end
