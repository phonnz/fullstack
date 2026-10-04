defmodule FullstackWeb.AdminAuthorizationTest do
  @moduledoc """
  Authorization tests for the `/admin` scope.

  These live in one file rather than being duplicated across the five
  per-resource admin LiveView test files, which each only cover the happy
  path for an authorized user.
  """
  use FullstackWeb.ConnCase

  import Phoenix.LiveViewTest
  import Fullstack.AccountsFixtures

  # ~p cannot be expanded in a module attribute, so the list is a function.
  defp admin_paths do
    [
      ~p"/admin/posts",
      ~p"/admin/customers",
      ~p"/admin/poss",
      ~p"/admin/transactions",
      ~p"/admin/devices"
    ]
  end

  describe "an authenticated non-admin" do
    setup %{conn: conn} do
      %{conn: log_in_user(conn, user_fixture())}
    end

    test "gets a 404 on every admin route", %{conn: conn} do
      # A 404 rather than a redirect: a redirect would confirm to any
      # logged-in user that the route exists.
      for path <- admin_paths() do
        assert_raise Ecto.NoResultsError, fn -> get(conn, path) end
      end
    end

    test "gets a 404 when connecting over the live socket", %{conn: conn} do
      for path <- admin_paths() do
        assert_raise Ecto.NoResultsError, fn -> live(conn, path) end
      end
    end
  end

  describe "a :staff user" do
    setup %{conn: conn} do
      %{conn: log_in_user(conn, user_fixture(role: :staff))}
    end

    test "is not treated as an admin", %{conn: conn} do
      assert_raise Ecto.NoResultsError, fn -> get(conn, ~p"/admin/posts") end
    end
  end

  describe "an anonymous visitor" do
    test "is redirected to the login page", %{conn: conn} do
      for path <- admin_paths() do
        conn = get(conn, path)
        assert redirected_to(conn) == ~p"/users/log_in"
      end
    end
  end

  describe "an admin" do
    setup %{conn: conn} do
      %{conn: log_in_user(conn, admin_fixture())}
    end

    test "reaches every admin route", %{conn: conn} do
      for path <- admin_paths() do
        assert {:ok, _lv, _html} = live(conn, path)
      end
    end
  end

  describe "account settings" do
    test "stay reachable for a plain :user", %{conn: conn} do
      conn = log_in_user(conn, user_fixture())
      assert {:ok, _lv, html} = live(conn, ~p"/users/settings")
      assert html =~ "Settings"
    end
  end
end
