defmodule FullstackWeb.TransactionLiveTest do
  use FullstackWeb.ConnCase

  import Phoenix.LiveViewTest
  import Fullstack.FinancialFixtures

  @update_attrs %{amount: 43}
  @invalid_attrs %{amount: nil}

  defp create_transaction(%{conn: conn}) do
    transaction = transaction_fixture()
    user = Fullstack.AccountsFixtures.user_fixture()
    %{conn: log_in_user(conn, user), transaction: transaction}
  end

  describe "Index" do
    setup [:create_transaction]

    test "lists all transactions", %{conn: conn} do
      {:ok, _index_live, html} = live(conn, ~p"/admin/transactions")

      assert html =~ "Transactions"
    end

    test "updates transaction in listing", %{conn: conn, transaction: transaction} do
      {:ok, index_live, _html} = live(conn, ~p"/admin/transactions")

      assert index_live |> element("#transactions-#{transaction.id} a", "Edit") |> render_click() =~
               "Edit Transaction"

      assert_patch(index_live, ~p"/admin/transactions/#{transaction}/edit")

      assert index_live
             |> form("#transaction-form", transaction: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#transaction-form", transaction: @update_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/admin/transactions")

      html = render(index_live)
      assert html =~ "Transaction updated successfully"
    end

    test "deletes transaction in listing", %{conn: conn, transaction: transaction} do
      {:ok, index_live, _html} = live(conn, ~p"/admin/transactions")

      assert index_live
             |> element("#transactions-#{transaction.id} a", "Delete")
             |> render_click()

      refute has_element?(index_live, "#transactions-#{transaction.id}")
    end
  end

  describe "Show" do
    setup [:create_transaction]

    test "displays transaction", %{conn: conn, transaction: transaction} do
      {:ok, _show_live, html} = live(conn, ~p"/admin/transactions/#{transaction}")

      assert html =~ "Transaction"
    end

    test "updates transaction within modal", %{conn: conn, transaction: transaction} do
      {:ok, show_live, _html} = live(conn, ~p"/admin/transactions/#{transaction}")

      assert show_live |> element("a", "Edit") |> render_click() =~
               "Edit Transaction"

      assert_patch(show_live, ~p"/admin/transactions/#{transaction}/show/edit")

      assert show_live
             |> form("#transaction-form", transaction: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert show_live
             |> form("#transaction-form", transaction: @update_attrs)
             |> render_submit()

      assert_patch(show_live, ~p"/admin/transactions/#{transaction}")

      html = render(show_live)
      assert html =~ "Transaction updated successfully"
    end
  end
end
