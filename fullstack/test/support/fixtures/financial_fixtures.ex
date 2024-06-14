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
    {:ok, transaction} =
      attrs
      |> Enum.into(%{
        amount: 42
      })
      |> Fullstack.Financial.create_transaction()

    transaction
  end
end
