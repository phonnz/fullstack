defmodule FullstackWeb.HostRewriteIntegrationTest do
  use FullstackWeb.ConnCase

  test "chat host root serves the chat page", %{conn: conn} do
    conn = get(%{conn | host: "chat.agentson.live"}, "/")

    assert html_response(conn, 200) =~ "Hooah!"
  end

  test "bare host root serves the about page", %{conn: conn} do
    conn = get(%{conn | host: "agentson.live"}, "/")

    assert html_response(conn, 200) =~ "Happy Demos!"
  end

  test "demos host root serves the home page unchanged", %{conn: conn} do
    conn = get(%{conn | host: "demos.agentson.live"}, "/")

    assert html_response(conn, 200)
    refute conn.request_path == "/chat"
    refute conn.request_path == "/about"
  end
end
