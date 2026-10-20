defmodule FullstackWeb.BusinessDiscoveryLiveTest do
  use FullstackWeb.ConnCase
  import Phoenix.LiveViewTest

  describe "anonymous visitor" do
    test "sees the landing page with a call-to-action to log in or register", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/business-discovery")

      assert view.module == FullstackWeb.BusinessDiscoveryLive.Index

      assert html =~ ~s(href="/users/log_in") or html =~ ~s(href="/users/register")
    end
  end

  describe "signed-in user" do
    setup :register_and_log_in_user

    test "sees a link into the evaluate flow", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/business-discovery")

      assert view.module == FullstackWeb.BusinessDiscoveryLive.Index
      assert html =~ ~s(href="/business-discovery/evaluate")
    end
  end
end
