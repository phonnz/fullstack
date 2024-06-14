defmodule FullstackWeb.CustomerLiveTest do
  use FullstackWeb.ConnCase

  import Phoenix.LiveViewTest
  import Fullstack.CustomersFixtures

  @create_attrs %{full_name: "some full_name", email: "some email"}
  @update_attrs %{full_name: "some updated full_name", email: "some updated email"}
  @invalid_attrs %{full_name: nil, email: nil}

  defp create_customer(_) do
    customer = customer_fixture()
    %{customer: customer}
  end

  describe "Index" do
    setup [:create_customer]

    test "lists all customers", %{conn: conn, customer: customer} do
      {:ok, _index_live, html} = live(conn, ~p"/customers")

      assert html =~ "Listing Customers"
      assert html =~ customer.full_name
    end

    test "saves new customer", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/customers")

      assert index_live |> element("a", "New Customer") |> render_click() =~
               "New Customer"

      assert_patch(index_live, ~p"/customers/new")

      assert index_live
             |> form("#customer-form", customer: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#customer-form", customer: @create_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/customers")

      html = render(index_live)
      assert html =~ "Customer created successfully"
      assert html =~ "some full_name"
    end

    test "updates customer in listing", %{conn: conn, customer: customer} do
      {:ok, index_live, _html} = live(conn, ~p"/customers")

      assert index_live |> element("#customers-#{customer.id} a", "Edit") |> render_click() =~
               "Edit Customer"

      assert_patch(index_live, ~p"/customers/#{customer}/edit")

      assert index_live
             |> form("#customer-form", customer: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#customer-form", customer: @update_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/customers")

      html = render(index_live)
      assert html =~ "Customer updated successfully"
      assert html =~ "some updated full_name"
    end

    test "deletes customer in listing", %{conn: conn, customer: customer} do
      {:ok, index_live, _html} = live(conn, ~p"/customers")

      assert index_live |> element("#customers-#{customer.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#customers-#{customer.id}")
    end
  end

  describe "Show" do
    setup [:create_customer]

    test "displays customer", %{conn: conn, customer: customer} do
      {:ok, _show_live, html} = live(conn, ~p"/customers/#{customer}")

      assert html =~ "Show Customer"
      assert html =~ customer.full_name
    end

    test "updates customer within modal", %{conn: conn, customer: customer} do
      {:ok, show_live, _html} = live(conn, ~p"/customers/#{customer}")

      assert show_live |> element("a", "Edit") |> render_click() =~
               "Edit Customer"

      assert_patch(show_live, ~p"/customers/#{customer}/show/edit")

      assert show_live
             |> form("#customer-form", customer: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert show_live
             |> form("#customer-form", customer: @update_attrs)
             |> render_submit()

      assert_patch(show_live, ~p"/customers/#{customer}")

      html = render(show_live)
      assert html =~ "Customer updated successfully"
      assert html =~ "some updated full_name"
    end
  end
end
