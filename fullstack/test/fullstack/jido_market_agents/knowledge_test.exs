defmodule Fullstack.JidoMarketAgents.KnowledgeTest do
  use ExUnit.Case, async: false

  alias Fullstack.JidoMarketAgents.Knowledge

  defmodule ConfiguredKnowledge do
    def fetch(key), do: Process.get({__MODULE__, key}, {:error, :not_configured})
  end

  setup do
    previous = Application.fetch_env(:fullstack, :knowledge_module)
    Application.delete_env(:fullstack, :knowledge_module)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:fullstack, :knowledge_module, value)
        :error -> Application.delete_env(:fullstack, :knowledge_module)
      end
    end)

    :ok
  end

  test "fetch(:tech_adoption) loads priv content and missing or blank configured content fails before provider dispatch" do
    path = Application.app_dir(:fullstack, "priv/knowledge/guia-implementacion-ia-pymes.md")
    assert {:ok, content} = Knowledge.fetch(:tech_adoption)
    assert content == File.read!(path)
    if File.exists?("guia_implementacion_ia_pymes.md") do
      assert content == File.read!("guia_implementacion_ia_pymes.md")
    end

    Application.put_env(:fullstack, :knowledge_module, ConfiguredKnowledge)

    for key <- [:six_systems, :tech_adoption] do
      Process.put({ConfiguredKnowledge, key}, {:ok, "Configured grounding"})
      assert {:ok, "Configured grounding"} = Knowledge.fetch(key)

      for configured <- [
            {:error, :not_configured},
            {:error, :enoent},
            {:ok, ""},
            {:ok, " \n\t "},
            {:ok, nil},
            {:ok, 123}
          ] do
        Process.put({ConfiguredKnowledge, key}, configured)
        # The consumer's provider call is reachable only after successful grounding resolution.
        result =
          with {:ok, _grounding} <- Knowledge.fetch(key), do: send(self(), :provider_dispatch)

        assert result == {:error, :not_configured}
        refute_received :provider_dispatch
      end
    end

    assert {:error, :unknown_knowledge} = Knowledge.fetch(:unsupported)
    Application.put_env(:fullstack, :knowledge_module, Knowledge)
    assert {:ok, ^content} = Knowledge.fetch(:tech_adoption)
    Application.put_env(:fullstack, :knowledge_module, nil)
    assert {:error, :not_configured} = Knowledge.fetch(:six_systems)
  end

  test "fetch(:six_systems) reads the release-safe priv file" do
    path = Application.app_dir(:fullstack, "priv/knowledge/six-systems-to-scale-a-business.md")
    assert {:ok, content} = Knowledge.fetch(:six_systems)
    assert content == File.read!(path)
    # Byte-equality with the developer's root-level original is a dev-tree
    # nicety only: the root file is untracked, so a clean checkout must not
    # depend on it (the committed priv copy is the release artifact).
    if File.exists?("six-systems-to-scale-a-business.md") do
      assert content == File.read!("six-systems-to-scale-a-business.md")
    end
    assert content =~ "## 6. Information"
    assert {:error, :unknown_knowledge} = Knowledge.fetch(:unsupported)
    assert {:error, :unknown_knowledge} = Knowledge.fetch("../../etc/passwd")
  end
end
