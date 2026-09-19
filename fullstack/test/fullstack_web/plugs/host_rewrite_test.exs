defmodule FullstackWeb.Plugs.HostRewriteTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias FullstackWeb.Plugs.HostRewrite

  defp call(host, path) do
    :get
    |> conn(path)
    |> Map.put(:host, host)
    |> HostRewrite.call(HostRewrite.init([]))
  end

  test "chat host root rewrites to /chat" do
    conn = call("chat.agentson.live", "/")

    assert conn.path_info == ["chat"]
    assert conn.request_path == "/chat"
  end

  test "bare host root rewrites to /about" do
    conn = call("agentson.live", "/")

    assert conn.path_info == ["about"]
    assert conn.request_path == "/about"
  end

  test "demos host root is left untouched" do
    conn = call("demos.agentson.live", "/")

    assert conn.path_info == []
    assert conn.request_path == "/"
  end

  test "chat host non-root path is left untouched" do
    conn = call("chat.agentson.live", "/urls")

    assert conn.path_info == ["urls"]
    assert conn.request_path == "/urls"
  end

  test "unknown host root is left untouched" do
    conn = call("unknown.example.com", "/")

    assert conn.path_info == []
    assert conn.request_path == "/"
  end
end
