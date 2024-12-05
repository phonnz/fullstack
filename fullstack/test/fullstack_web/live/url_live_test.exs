defmodule FullstackWeb.UrlLiveTest do
  use FullstackWeb.ConnCase

  import Phoenix.LiveViewTest
  import Fullstack.UrlsFixtures

  @create_attrs %{origin: "some origin", destiny: "some destiny", visit_count: 42}
  @update_attrs %{origin: "some updated origin", destiny: "some updated destiny", visit_count: 43}
  @invalid_attrs %{origin: nil, destiny: nil, visit_count: nil}

  defp create_url(_) do
    url = url_fixture()
    %{url: url}
  end

  describe "Index" do
    setup [:create_url]

    test "lists all ulrs", %{conn: conn, url: url} do
      {:ok, _index_live, html} = live(conn, ~p"/ulrs")

      assert html =~ "Listing Ulrs"
      assert html =~ url.origin
    end

    test "saves new url", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/ulrs")

      assert index_live |> element("a", "New Url") |> render_click() =~
               "New Url"

      assert_patch(index_live, ~p"/ulrs/new")

      assert index_live
             |> form("#url-form", url: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#url-form", url: @create_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/ulrs")

      html = render(index_live)
      assert html =~ "Url created successfully"
      assert html =~ "some origin"
    end

    test "updates url in listing", %{conn: conn, url: url} do
      {:ok, index_live, _html} = live(conn, ~p"/ulrs")

      assert index_live |> element("#ulrs-#{url.id} a", "Edit") |> render_click() =~
               "Edit Url"

      assert_patch(index_live, ~p"/ulrs/#{url}/edit")

      assert index_live
             |> form("#url-form", url: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#url-form", url: @update_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/ulrs")

      html = render(index_live)
      assert html =~ "Url updated successfully"
      assert html =~ "some updated origin"
    end

    test "deletes url in listing", %{conn: conn, url: url} do
      {:ok, index_live, _html} = live(conn, ~p"/ulrs")

      assert index_live |> element("#ulrs-#{url.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#ulrs-#{url.id}")
    end
  end

  describe "Show" do
    setup [:create_url]

    test "displays url", %{conn: conn, url: url} do
      {:ok, _show_live, html} = live(conn, ~p"/ulrs/#{url}")

      assert html =~ "Show Url"
      assert html =~ url.origin
    end

    test "updates url within modal", %{conn: conn, url: url} do
      {:ok, show_live, _html} = live(conn, ~p"/ulrs/#{url}")

      assert show_live |> element("a", "Edit") |> render_click() =~
               "Edit Url"

      assert_patch(show_live, ~p"/ulrs/#{url}/show/edit")

      assert show_live
             |> form("#url-form", url: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert show_live
             |> form("#url-form", url: @update_attrs)
             |> render_submit()

      assert_patch(show_live, ~p"/ulrs/#{url}")

      html = render(show_live)
      assert html =~ "Url updated successfully"
      assert html =~ "some updated origin"
    end
  end
end
