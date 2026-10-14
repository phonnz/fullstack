defmodule Fullstack.JidoMarketAgents.Agents.MarketResearcher do
  @moduledoc """
  Jido agent requesting structured, explicitly unverified market investigation.
  """

  use Jido.Agent,
    name: "market_researcher",
    description: "Researches structured market evidence",
    schema: [
      country: [type: :string, required: false],
      city: [type: :string, required: false],
      business_market: [type: :string, required: false],
      final_product_proposal: [type: :string, required: false]
    ]

  alias Fullstack.JidoMarketAgents.LLM
  alias Fullstack.JidoMarketAgents.Agents.MarketResearchOutput

  def research(agent) do
    prompt = prompt(agent)

    messages = [
      %{
        "role" => "system",
        "content" => "You are a market research analyst. Provide concise, factual analysis."
      },
      %{"role" => "user", "content" => prompt}
    ]

    case LLM.chat_completion(:researcher, messages,
           response_format: {:json_object, MarketResearchOutput.schema()}
         ) do
      {:ok, content} ->
        parse_result(content)

      {:error, reason} ->
        {:error, {:research_failed, reason}}
    end
  end

  @doc "Builds a no-retrieval investigation prompt without claiming verified evidence."
  def prompt(agent) do
    state = agent.state

    location =
      if state[:city] in [nil, ""], do: state.country, else: "#{state.city}, #{state.country}"

    """
    Investigate the market for #{state.final_product_proposal} in #{location}, sector #{state.business_market}.
    Return ONLY JSON matching the supplied MarketResearchOutput schema.
    Include competitor claims in market_evidence, opportunity hypotheses in market_gaps,
    and demand_signals. Label every claim unverified and include confidence (low/medium/high).
    No retrieval tool is available: sources must be empty and evidence_refs must be empty.
    Do not fabricate URLs, citations, verification, demand measurements, or company facts.
    Explain uncertainty, knowledge freshness, and missing validation in limitations.
    Distinguish market hypotheses from user facts; do not decide a viable offer or a strategy.
    """
  end

  defp parse_result(content) when is_binary(content) do
    content = String.trim(content)

    json =
      case Regex.run(~r/\A```(?:json)?\s*(.*?)\s*```\z/s, content, capture: :all_but_first) do
        [json] -> json
        nil -> content
      end

    case Jason.decode(json) do
      {:ok, raw} when is_map(raw) ->
        case MarketResearchOutput.normalize_map(raw) do
          {:error, _} = error -> error
          result -> {:ok, result}
        end

      {:ok, _} ->
        {:error, {:parse_failed, :not_a_map}}

      {:error, reason} ->
        {:error, {:parse_failed, {:json_parse, reason}}}
    end
  end

  defp parse_result(_content), do: {:error, {:parse_failed, :invalid_content}}
end
