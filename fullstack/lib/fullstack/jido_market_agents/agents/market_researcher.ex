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
    country = agent.state.country
    city = agent.state[:city]
    market = agent.state.business_market
    product = agent.state.final_product_proposal

    location = if city && city != "", do: "#{city}, #{country}", else: country

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
        {:ok, %{research_result: content, location: location, market: market, product: product}}

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
end
