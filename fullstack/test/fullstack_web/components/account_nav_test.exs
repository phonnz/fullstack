defmodule FullstackWeb.Components.AccountNavTest do
  use FullstackWeb.ConnCase, async: true

  import Phoenix.Component, only: [sigil_H: 2]
  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]
  import Fullstack.AccountsFixtures

  alias FullstackWeb.Layouts

  defp render_nav(current_user) do
    assigns = %{current_user: current_user}

    rendered_to_string(~H"""
    <Layouts.account_nav current_user={@current_user} />
    """)
  end

  test "an admin sees the Evaluations link" do
    html = render_nav(admin_fixture())

    assert html =~ "/evaluations"
    assert html =~ "Evaluations"
  end

  test "a plain user does not see the Evaluations link" do
    html = render_nav(user_fixture())

    refute html =~ "/evaluations"
  end

  test "a :staff user does not see the Evaluations link" do
    html = render_nav(user_fixture(role: :staff))

    refute html =~ "/evaluations"
  end

  test "an anonymous visitor does not see the Evaluations link" do
    html = render_nav(nil)

    refute html =~ "/evaluations"
    assert html =~ "Log in"
  end
end
