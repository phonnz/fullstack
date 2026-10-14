defmodule Fullstack.JidoMarketAgents.KnowledgeTest do
  use ExUnit.Case, async: false

  alias Fullstack.JidoMarketAgents.Knowledge

  test "fetch(:six_systems) reads the release-safe priv file" do
    path = Application.app_dir(:fullstack, "priv/knowledge/six-systems-to-scale-a-business.md")
    assert {:ok, content} = Knowledge.fetch(:six_systems)
    assert content == File.read!(path)
    assert content == File.read!("six-systems-to-scale-a-business.md")
    assert content =~ "## 6. Information"
    assert {:error, :unknown_knowledge} = Knowledge.fetch(:unsupported)
    assert {:error, :unknown_knowledge} = Knowledge.fetch("../../etc/passwd")
  end
end
