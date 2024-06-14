defmodule Fullstack.FinancialTest do
  use Fullstack.DataCase

  alias Fullstack.Financial

  describe "poss" do
    alias Fullstack.Financial.Pos

    import Fullstack.FinancialFixtures

    @invalid_attrs %{name: nil}

    test "list_poss/0 returns all poss" do
      pos = pos_fixture()
      assert Financial.list_poss() == [pos]
    end

    test "get_pos!/1 returns the pos with given id" do
      pos = pos_fixture()
      assert Financial.get_pos!(pos.id) == pos
    end

    test "create_pos/1 with valid data creates a pos" do
      valid_attrs = %{name: "some name"}

      assert {:ok, %Pos{} = pos} = Financial.create_pos(valid_attrs)
      assert pos.name == "some name"
    end

    test "create_pos/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Financial.create_pos(@invalid_attrs)
    end

    test "update_pos/2 with valid data updates the pos" do
      pos = pos_fixture()
      update_attrs = %{name: "some updated name"}

      assert {:ok, %Pos{} = pos} = Financial.update_pos(pos, update_attrs)
      assert pos.name == "some updated name"
    end

    test "update_pos/2 with invalid data returns error changeset" do
      pos = pos_fixture()
      assert {:error, %Ecto.Changeset{}} = Financial.update_pos(pos, @invalid_attrs)
      assert pos == Financial.get_pos!(pos.id)
    end

    test "delete_pos/1 deletes the pos" do
      pos = pos_fixture()
      assert {:ok, %Pos{}} = Financial.delete_pos(pos)
      assert_raise Ecto.NoResultsError, fn -> Financial.get_pos!(pos.id) end
    end

    test "change_pos/1 returns a pos changeset" do
      pos = pos_fixture()
      assert %Ecto.Changeset{} = Financial.change_pos(pos)
    end
  end

  describe "transactions" do
    alias Fullstack.Financial.Transaction

    import Fullstack.FinancialFixtures

    @invalid_attrs %{amount: nil}

    test "list_transactions/0 returns all transactions" do
      transaction = transaction_fixture()
      assert Financial.list_transactions() == [transaction]
    end

    test "get_transaction!/1 returns the transaction with given id" do
      transaction = transaction_fixture()
      assert Financial.get_transaction!(transaction.id) == transaction
    end

    test "create_transaction/1 with valid data creates a transaction" do
      valid_attrs = %{amount: 42}

      assert {:ok, %Transaction{} = transaction} = Financial.create_transaction(valid_attrs)
      assert transaction.amount == 42
    end

    test "create_transaction/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Financial.create_transaction(@invalid_attrs)
    end

    test "update_transaction/2 with valid data updates the transaction" do
      transaction = transaction_fixture()
      update_attrs = %{amount: 43}

      assert {:ok, %Transaction{} = transaction} = Financial.update_transaction(transaction, update_attrs)
      assert transaction.amount == 43
    end

    test "update_transaction/2 with invalid data returns error changeset" do
      transaction = transaction_fixture()
      assert {:error, %Ecto.Changeset{}} = Financial.update_transaction(transaction, @invalid_attrs)
      assert transaction == Financial.get_transaction!(transaction.id)
    end

    test "delete_transaction/1 deletes the transaction" do
      transaction = transaction_fixture()
      assert {:ok, %Transaction{}} = Financial.delete_transaction(transaction)
      assert_raise Ecto.NoResultsError, fn -> Financial.get_transaction!(transaction.id) end
    end

    test "change_transaction/1 returns a transaction changeset" do
      transaction = transaction_fixture()
      assert %Ecto.Changeset{} = Financial.change_transaction(transaction)
    end
  end
end
