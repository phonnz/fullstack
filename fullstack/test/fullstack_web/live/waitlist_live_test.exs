defmodule FullstackWeb.WaitlistLiveTest do
  use FullstackWeb.ConnCase
  import Phoenix.LiveViewTest

  alias Fullstack.Waitlist

  describe "anonymous visitor" do
    test "renders marketing copy and the signup form", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/waitlist")

      assert view.module == FullstackWeb.WaitlistLive.Index
      assert html =~ "business"
      assert html =~ "founding cohort"
      assert html =~ "I don&#39;t know yet"
      refute html =~ "aria-label=\"Fullstack home\""
      refute html =~ "id=\"main-content\""
      assert has_element?(view, "form")
      assert has_element?(view, "input[name='signup[discount_code]']")
    end

    test "places strategy methodology after all assessment cards", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/waitlist")

      assert has_element?(view, ".wl-steps-section h2", "How the assessment works")
      assert has_element?(view, ".wl-steps > .wl-step:nth-child(4) h3", "Walk to MVP")
      assert has_element?(view, ".wl-steps-section + #strategy-methodology")
      assert has_element?(view, "#strategy-methodology + .wl-framework")
      assert has_element?(view, "#strategy-methodology h2", "Our strategy methodology")

      assert has_element?(
               view,
               "ai-strategy-animation#waitlist-strategy-animation[phx-update='ignore']"
             )

      for heading <- [
            "Describe the idea",
            "Agents size the market",
            "See the numbers",
            "Walk to MVP"
          ] do
        assert html =~ heading
      end
    end

    test "submitting a valid email with no country creates a signup with country: nil", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/waitlist")

      html =
        view
        |> form("#waitlist-signup-form", signup: %{email: "lead@example.com"})
        |> render_submit()

      assert html =~ "you&#39;re on the list" or html =~ "you're on the list"

      assert [%Waitlist.Signup{email: "lead@example.com", country: nil}] =
               Fullstack.Repo.all(Waitlist.Signup)
    end

    test "submitting a valid email with a selected country stores that country", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/waitlist")

      view
      |> form("#waitlist-signup-form", signup: %{email: "spain@example.com", country: "Spain"})
      |> render_submit()

      assert [%Waitlist.Signup{email: "spain@example.com", country: "Spain"}] =
               Fullstack.Repo.all(Waitlist.Signup)
    end

    test "submitting a valid email with a discount code stores that code", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/waitlist")

      view
      |> form("#waitlist-signup-form",
        signup: %{email: "coded@example.com", discount_code: "SAVE20"}
      )
      |> render_submit()

      assert [%Waitlist.Signup{email: "coded@example.com", discount_code: "SAVE20"}] =
               Fullstack.Repo.all(Waitlist.Signup)
    end

    test "duplicate email surfaces a changeset error without crashing", %{conn: conn} do
      {:ok, _signup} = Waitlist.create_signup(%{email: "dup@example.com"})

      {:ok, view, _html} = live(conn, ~p"/waitlist")

      html =
        view
        |> form("#waitlist-signup-form", signup: %{email: "dup@example.com"})
        |> render_submit()

      assert html =~ "has already been taken"
      assert Fullstack.Repo.aggregate(Waitlist.Signup, :count) == 1
    end
  end
end
