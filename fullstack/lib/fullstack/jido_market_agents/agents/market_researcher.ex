defmodule Fullstack.JidoMarketAgents.Agents.MarketResearcher do
  @moduledoc """
  Jido agent that researches market presence using MIMO LLM.
  Given country, market, and product, asks the LLM if companies exist.
  """

  use Jido.Agent,
    name: "market_researcher",
    description: "Researches market presence via MIMO LLM",
    schema: [
      country: [type: :string, required: false],
      city: [type: :string, required: false],
      business_market: [type: :string, required: false],
      final_product_proposal: [type: :string, required: false]
    ]

  alias Fullstack.JidoMarketAgents.LLM

  def research(agent) do
    country = agent.state.country
    city = agent.state[:city]
    market = agent.state.business_market
    product = agent.state.final_product_proposal

    location = if city && city != "", do: "#{city}, #{country}", else: country

    prompt = """
    You are a market research assistant. Based on your knowledge, analyze the following:

    Location: #{location}
    Business Market: #{market}
    Product/Service: #{product}

    Is there an established company in #{location} that operates in the #{market} sector and offers a similar product or service to "#{product}"?

    Provide:
    1. Whether such companies exist (yes/no)
    2. If yes, name up to 3 examples with brief descriptions
    3. Market opportunity assessment (gaps, competition level)
    4. Brief recommendation

    Be concise and factual. If you don't have specific data, say so clearly.
    """

    messages = [
      %{
        "role" => "system",
        "content" => "You are a market research analyst. Provide concise, factual analysis."
      },
      %{"role" => "user", "content" => prompt}
    ]

    case LLM.chat_completion(:researcher, messages, response_format: :text) do
      {:ok, content} ->
        {:ok, %{research_result: content, location: location, market: market, product: product}}

      {:error, reason} ->
        {:error, {:research_failed, reason}}
    end
  end
end
