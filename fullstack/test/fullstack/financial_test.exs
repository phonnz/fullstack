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
end
