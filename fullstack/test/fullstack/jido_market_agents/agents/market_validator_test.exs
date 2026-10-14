defmodule Fullstack.JidoMarketAgents.Agents.MarketValidatorTest do
  use ExUnit.Case, async: true

  alias Fullstack.JidoMarketAgents.Agents.{ExtractionOutput, MarketValidator}

  @diagnosis_fields [
    :team_size,
    :current_tools_systems,
    :repetitive_processes_pain_points,
    :digital_maturity,
    :metrics_baselines
  ]

  describe "new/1" do
    test "new/1 exposes all diagnosis state fields" do
      agent = MarketValidator.new()

      for field <- @diagnosis_fields do
        assert Map.has_key?(agent.state, field)
        assert Map.get(agent.state, field) == nil
      end
    end

    test "output_language is state metadata, not an extractable diagnosis field" do
      agent = MarketValidator.new()

      assert Map.has_key?(agent.state, :output_language)
      assert Map.get(agent.state, :output_language) == nil
      refute :output_language in ExtractionOutput.fields()
    end
  end

  describe "extraction prompt" do
    test "text extraction prompt explains diagnosis and explicit unknown states" do
      prompt = MarketValidator.extraction_prompt()

      # diagnosis field definitions
      assert prompt =~ "team_size"
      assert prompt =~ "current_tools_systems"
      assert prompt =~ "repetitive_processes_pain_points"
      assert prompt =~ "digital_maturity"
      assert prompt =~ "metrics_baselines"

      # explicit unknown states must be requested, never guessed
      assert prompt =~ "unknown"
      assert prompt =~ "\"status\""
      assert prompt =~ "Do not invent"

      # commercial fields stay in the prompt
      assert prompt =~ "country"
      assert prompt =~ "product_price"
    end
  end

  describe "prompt and summary rendering" do
    test "missing prompt and summary render diagnosis fields without raw maps" do
      prompt =
        MarketValidator.format_missing_prompt([
          :team_size,
          :current_tools_systems,
          :repetitive_processes_pain_points,
          :digital_maturity,
          :metrics_baselines
        ])

      assert prompt =~ "team size"
      assert prompt =~ "current tools and systems"
      assert prompt =~ "repetitive processes and pain points"
      assert prompt =~ "digital maturity"
      assert prompt =~ "baseline metrics"

      {:ok, agent} =
        MarketValidator.extract_fields(MarketValidator.new(), %{
          "country" => "Spain",
          "team_size" => %{"status" => "known", "count" => 5, "notes" => "two founders"},
          "current_tools_systems" => %{
            "status" => "known",
            "items" => [
              %{
                "name" => "Slack",
                "category" => "communication",
                "purpose" => "team chat",
                "integration_notes" => nil
              }
            ]
          },
          "repetitive_processes_pain_points" => %{"status" => "none", "items" => []},
          "digital_maturity" => %{"level" => "manual", "evidence" => "spreadsheets"},
          "metrics_baselines" => %{"status" => "unknown", "items" => []}
        })

      summary = MarketValidator.format_extraction_summary(agent)

      refute summary =~ "%{"
      assert summary =~ "Team size: 5"
      assert summary =~ "Current tools and systems: 1 item"
      assert summary =~ "Slack"
      assert summary =~ "Repetitive processes and pain points: none"
      assert summary =~ "Digital maturity: manual"
      assert summary =~ "Baseline metrics: unknown"
    end
  end

  describe "check_completeness/1" do
    test "check_completeness/1 accepts explicit unknown and rejects top-level nil" do
      answered = %{
        country: "Spain",
        business_market: "SaaS",
        initial_budget: "10000 EUR",
        final_product_proposal: "Inventory app",
        product_price: "20 EUR",
        team_size: %{status: "unknown", count: nil, notes: nil},
        current_tools_systems: %{status: "unknown", items: []},
        repetitive_processes_pain_points: %{status: "unknown", items: []},
        digital_maturity: %{level: "unknown", evidence: nil},
        metrics_baselines: %{status: "unknown", items: []}
      }

      {:ok, agent} = MarketValidator.extract_fields(MarketValidator.new(), answered)

      assert {:complete, data} = MarketValidator.check_completeness(agent)
      assert data.team_size == %{status: "unknown", count: nil, notes: nil}
      # city stays optional: an absent city does not block completeness
      assert data.city == nil

      # top-level nil is not an explicit answer: it stays missing
      {:ok, agent} =
        MarketValidator.extract_fields(
          MarketValidator.new(),
          Map.put(answered, :team_size, nil)
        )

      assert {:incomplete, missing} = MarketValidator.check_completeness(agent)
      assert missing == [:team_size]
      refute :city in missing
    end
  end

  describe "extract_fields/2 map fast path" do
    test "stores normalized diagnosis values explicitly before set/2" do
      agent = MarketValidator.new()

      assert {:ok, agent} =
               MarketValidator.extract_fields(agent, %{
                 "country" => "Spain",
                 "team_size" => %{"status" => "known", "count" => 5},
                 "digital_maturity" => %{"level" => "manual"}
               })

      assert agent.state.country == "Spain"
      assert agent.state.team_size == %{status: "known", count: 5, notes: nil}
      assert agent.state.digital_maturity == %{level: "manual", evidence: nil}

      summary = MarketValidator.format_extraction_summary(agent)
      assert summary =~ "Team size"
    end

    test "malformed non-null diagnosis returns a tagged error and leaves prior data unchanged" do
      agent = MarketValidator.new()
      {:ok, agent} = MarketValidator.extract_fields(agent, %{country: "Spain"})

      assert {:error, {:invalid_diagnosis, :team_size, :invalid_status}} =
               MarketValidator.extract_fields(agent, %{"team_size" => %{"status" => "banana"}})

      assert agent.state.country == "Spain"
      assert Map.get(agent.state, :team_size) == nil
    end
  end
end
