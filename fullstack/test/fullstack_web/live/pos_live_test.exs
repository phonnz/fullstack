defmodule FullstackWeb.PosLiveTest do
  use FullstackWeb.ConnCase

  import Phoenix.LiveViewTest
  import Fullstack.FinancialFixtures

  @create_attrs %{name: "some name"}
  @update_attrs %{name: "some updated name"}
  @invalid_attrs %{name: nil}

  defp create_pos(_) do
    pos = pos_fixture()
    %{pos: pos}
  end

  describe "Index" do
    setup [:create_pos]

    test "lists all poss", %{conn: conn, pos: pos} do
      {:ok, _index_live, html} = live(conn, ~p"/poss")

      assert html =~ "Listing Poss"
      assert html =~ pos.name
    end

    test "saves new pos", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/poss")

      assert index_live |> element("a", "New Pos") |> render_click() =~
               "New Pos"

      assert_patch(index_live, ~p"/poss/new")

      assert index_live
             |> form("#pos-form", pos: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#pos-form", pos: @create_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/poss")

      html = render(index_live)
      assert html =~ "Pos created successfully"
      assert html =~ "some name"
    end

    test "updates pos in listing", %{conn: conn, pos: pos} do
      {:ok, index_live, _html} = live(conn, ~p"/poss")

      assert index_live |> element("#poss-#{pos.id} a", "Edit") |> render_click() =~
               "Edit Pos"

      assert_patch(index_live, ~p"/poss/#{pos}/edit")

      assert index_live
             |> form("#pos-form", pos: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#pos-form", pos: @update_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/poss")

      html = render(index_live)
      assert html =~ "Pos updated successfully"
      assert html =~ "some updated name"
    end

    test "deletes pos in listing", %{conn: conn, pos: pos} do
      {:ok, index_live, _html} = live(conn, ~p"/poss")

      assert index_live |> element("#poss-#{pos.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#poss-#{pos.id}")
    end
  end

  describe "Show" do
    setup [:create_pos]

    test "displays pos", %{conn: conn, pos: pos} do
      {:ok, _show_live, html} = live(conn, ~p"/poss/#{pos}")

      assert html =~ "Show Pos"
      assert html =~ pos.name
    end

    test "updates pos within modal", %{conn: conn, pos: pos} do
      {:ok, show_live, _html} = live(conn, ~p"/poss/#{pos}")

      assert show_live |> element("a", "Edit") |> render_click() =~
               "Edit Pos"

      assert_patch(show_live, ~p"/poss/#{pos}/show/edit")

      assert show_live
             |> form("#pos-form", pos: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert show_live
             |> form("#pos-form", pos: @update_attrs)
             |> render_submit()

      assert_patch(show_live, ~p"/poss/#{pos}")

      html = render(show_live)
      assert html =~ "Pos updated successfully"
      assert html =~ "some updated name"
    end
  end
end
