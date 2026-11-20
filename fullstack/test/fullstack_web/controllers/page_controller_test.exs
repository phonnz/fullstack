defmodule FullstackWeb.PageControllerTest do
  use FullstackWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Robust real-time"
  end
end
