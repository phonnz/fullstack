defmodule Fullstack.JidoMarketAgents.Agents.MarketResearcherTest do
  use ExUnit.Case, async: false

  alias Fullstack.JidoMarketAgents.Agents.{MarketResearcher, MarketResearchOutput}

  defmodule Backend do
    @behaviour Fullstack.JidoMarketAgents.LLM.Backend
    def capabilities(_), do: [:json_object]
    def validate_config(_), do: :ok

    def chat_completion(messages, opts) do
      send(self(), {:research_dispatch, messages, opts})
      Process.get(:research_reply, {:ok, "{}"})
    end
  end

  setup do
    config = Application.get_env(:fullstack, Fullstack.JidoMarketAgents, [])

    Application.put_env(
      :fullstack,
      Fullstack.JidoMarketAgents,
      Keyword.put(config, :researcher_backend, {Backend, model: "research-test"})
    )

    on_exit(fn -> Application.put_env(:fullstack, Fullstack.JidoMarketAgents, config) end)

    {:ok,
     agent:
       MarketResearcher.new(
         state: %{
           country: "Spain",
           city: "Madrid",
           business_market: "fintech",
           final_product_proposal: "Payment app"
         }
       )}
  end

  test "research prompt requests competitor evidence and unverified limitations", %{agent: agent} do
    MarketResearcher.research(agent)
    assert_received {:research_dispatch, messages, opts}
    assert opts[:response_format] == {:json_object, MarketResearchOutput.schema()}
    prompt = List.last(messages)["content"]
    assert prompt =~ "Madrid, Spain"
    assert prompt =~ "competitor"
    assert prompt =~ "unverified"
    assert prompt =~ "limitations"
    assert prompt =~ "sources must be empty"
    assert prompt =~ "market_gaps"
    assert prompt =~ "demand_signals"
    assert prompt == MarketResearcher.prompt(agent)
  end

  test "research/1 normalizes JSON and tags provider or parse failure", %{agent: agent} do
    raw = %{
      "market_evidence" => [%{"claim" => " Rival offers payments "}],
      "limitations" => ["No retrieval"]
    }

    Process.put(:research_reply, {:ok, Jason.encode!(raw)})
    assert {:ok, result} = MarketResearcher.research(agent)
    assert result == MarketResearchOutput.normalize_map(raw)
    assert hd(result.market_evidence).verification_status == "unverified"
    Process.put(:research_reply, {:ok, "```json\n#{Jason.encode!(raw)}\n```"})
    assert {:ok, ^result} = MarketResearcher.research(agent)
    Process.put(:research_reply, {:error, :offline})
    assert {:error, {:research_failed, :offline}} = MarketResearcher.research(agent)
    Process.put(:research_reply, {:ok, "not JSON"})

    assert {:error, {:parse_failed, {:json_parse, %Jason.DecodeError{}}}} =
             MarketResearcher.research(agent)

    Process.put(:research_reply, {:ok, "[]"})
    assert {:error, {:parse_failed, :not_a_map}} = MarketResearcher.research(agent)
    Process.put(:research_reply, {:ok, nil})
    assert {:error, {:parse_failed, :invalid_content}} = MarketResearcher.research(agent)
    Process.put(:research_reply, {:ok, ~s({"sources":["invented"]})})

    assert {:error, {:invalid_market_research, :sources, :retrieval_unavailable}} =
             MarketResearcher.research(agent)

    Process.put(:research_reply, {:ok, ~s({"_pipeline":{}})})
    assert {:error, {:reserved_key, :_pipeline}} = MarketResearcher.research(agent)
  end
end
