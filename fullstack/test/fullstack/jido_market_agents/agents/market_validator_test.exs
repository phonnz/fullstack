defmodule Fullstack.JidoMarketAgents.Agents.MarketValidatorTest do
  # Mutates and restores Application.get_env(:fullstack,
  # Fullstack.JidoMarketAgents, ...) for the text-path tests, so this
  # module must not run concurrently with other tests reading or writing
  # the same application env key (see llm_test.exs for the same rule).
  use ExUnit.Case, async: false

  alias Fullstack.JidoMarketAgents.Agents.{ExtractionOutput, MarketValidator}

  @app :fullstack
  @scope Fullstack.JidoMarketAgents

  # Fake validator backend whose extraction answers carry language hints,
  # mirroring the llm_test.exs / backend_dispatch_test.exs idiom.
  defmodule LanguageFakeBackend do
    @moduledoc false
    @behaviour Fullstack.JidoMarketAgents.LLM.Backend

    @impl true
    def chat_completion(messages, opts) do
      send(self(), {:backend_called, __MODULE__, messages, opts})
      user = messages |> List.last() |> Map.fetch!("content")
      {:ok, reply(user)}
    end

    defp reply("first text" <> _) do
      Jason.encode!(%{
        "country" => "Spain",
        "justification" => "The message explicitly names Spain.",
        "output_language" => "es",
        "language_switch_requested" => false
      })
    end

    defp reply("silent hint" <> _) do
      Jason.encode!(%{
        "city" => "Barcelona",
        "output_language" => "fr",
        "language_switch_requested" => false
      })
    end

    defp reply("explicit switch" <> _) do
      Jason.encode!(%{
        "output_language" => "en",
        "language_switch_requested" => true
      })
    end

    @impl true
    def capabilities(_opts), do: [:json_object]

    @impl true
    def validate_config(_opts), do: :ok
  end

  setup do
    original = Application.get_env(@app, @scope, [])

    on_exit(fn ->
      Application.put_env(@app, @scope, original)
    end)

    :ok
  end

  defp put_validator_backend(module) do
    base = Application.get_env(@app, @scope, [])
    Application.put_env(@app, @scope, Keyword.put(base, :validator_backend, {module, []}))
  end

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

    test "prompt declares an explicit flat top-level output shape" do
      prompt = MarketValidator.extraction_prompt()

      # the MiMo adapter discards the JSON schema, so "the supplied schema"
      # refers to nothing; the shape must be spelled out in the prompt itself
      refute prompt =~ "supplied schema"
      assert prompt =~ "OUTPUT SHAPE"

      expected_keys =
        ExtractionOutput.fields() ++
          [:justification, :output_language, :language_switch_requested]

      shape_keys =
        ~r/^\s+"([a-z_]+)":/m
        |> Regex.scan(prompt, capture: :all_but_first)
        |> List.flatten()

      assert shape_keys == Enum.map(expected_keys, &to_string/1)
    end

    test "prompt forbids envelopes and model-owned sufficiency, and requires every key" do
      prompt = MarketValidator.extraction_prompt()

      assert prompt =~ ~s(Do not wrap the fields in "data" or in any other object)
      assert prompt =~ ~s(Do not emit "sufficient" or "missing_fields")
      assert prompt =~ "Every key of the output shape must be present"
      assert prompt =~ "null for"
    end

    test "prompt defines the language metadata keys" do
      prompt = MarketValidator.extraction_prompt()

      assert prompt =~ "output_language: language code"
      assert prompt =~ "latest user message"
      assert prompt =~ "language_switch_requested: true only when"
      assert prompt =~ "explicitly asks"
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
      report = MarketValidator.assessment(agent)
      assert report.sufficient
      assert report.data == data
      assert report.missing_fields == []
      assert report.next_question == nil
      assert report.justification =~ "explicit unknown"
      assert List.last(agent.state.extraction_history).assessment == report

      # top-level nil is not an explicit answer: it stays missing
      {:ok, agent} =
        MarketValidator.extract_fields(
          MarketValidator.new(),
          Map.put(answered, :team_size, nil)
        )

      assert {:incomplete, missing} = MarketValidator.check_completeness(agent)
      assert missing == [:team_size]
      refute :city in missing
      report = MarketValidator.assessment(agent)
      refute report.sufficient
      assert report.missing_fields == [:team_size]
      assert report.data.team_size == nil
      assert report.justification =~ "team size"
      assert report.next_question =~ "team size"
      assert MarketValidator.format_extraction_summary(agent) =~ "Missing: team size"
    end
  end

  test "text extraction retains factual metadata and supplies nonrecursive accumulated context" do
    put_validator_backend(LanguageFakeBackend)
    {:ok, agent} = MarketValidator.extract_fields(MarketValidator.new(), "first text")
    assert_receive {:backend_called, _, _, _}
    report = MarketValidator.assessment(agent)
    assert report.model_justification == "The message explicitly names Spain."
    refute report.sufficient
    refute Map.has_key?(report.data, :justification)
    assert report.data.team_size == nil

    {:ok, updated} = MarketValidator.extract_fields(agent, "silent hint")
    assert_receive {:backend_called, _, messages, _}
    assert List.last(messages) == %{"role" => "user", "content" => "silent hint"}
    context = Enum.at(messages, 1)
    assert context["role"] == "system"
    assert context["content"] =~ "Prior state"
    assert context["content"] =~ "not an output template"
    assert context["content"] =~ "Spain"
    refute context["content"] =~ "extraction_history"
    assert updated.state.country == "Spain"
    assert updated.state.team_size == nil
    assert length(updated.state.extraction_history) == 2
    assert hd(updated.state.extraction_history).assessment == report
    refute Map.has_key?(report, :extraction_history)

    prompt = MarketValidator.extraction_prompt()
    assert prompt =~ "justification"
    assert prompt =~ "null"
    assert prompt =~ "explicitly says"
    refute prompt =~ "When the user does not provide a diagnosis answer, set"
  end

  describe "prior state context message" do
    test "is context-only prior_facts and still_missing, never an output template" do
      put_validator_backend(LanguageFakeBackend)

      {:ok, agent} =
        MarketValidator.extract_fields(MarketValidator.new(), %{
          country: "Spain",
          team_size: %{status: "known", count: 3}
        })

      {:ok, _updated} = MarketValidator.extract_fields(agent, "silent hint")
      assert_receive {:backend_called, _, messages, _}

      assert [%{"role" => "system"}, context, %{"role" => "user"}] = messages
      assert context["role"] == "system"
      assert [label, json] = String.split(context["content"], "\n", parts: 2)
      assert label =~ "context only"
      assert label =~ "not an output template"

      decoded = Jason.decode!(json)
      assert decoded |> Map.keys() |> Enum.sort() == ["prior_facts", "still_missing"]

      # only known facts are sent, so the shape cannot be mistaken for the reply shape
      assert decoded["prior_facts"] == %{
               "country" => "Spain",
               "team_size" => %{"status" => "known", "count" => 3, "notes" => nil}
             }

      assert decoded["still_missing"] ==
               agent
               |> MarketValidator.assessment()
               |> Map.fetch!(:missing_fields)
               |> Enum.map(&to_string/1)

      # sufficiency is application-owned and never sent to the model
      refute json =~ "sufficient"
      refute json =~ ~s("data")
      refute json =~ "missing_fields"
    end

    test "starts with empty prior facts and every required field still missing" do
      put_validator_backend(LanguageFakeBackend)

      {:ok, _agent} = MarketValidator.extract_fields(MarketValidator.new(), "first text")
      assert_receive {:backend_called, _, messages, _}

      [_label, json] =
        messages |> Enum.at(1) |> Map.fetch!("content") |> String.split("\n", parts: 2)

      decoded = Jason.decode!(json)

      assert decoded["prior_facts"] == %{}
      assert length(decoded["still_missing"]) == 10
    end
  end

  test "assessment is available before the first extraction and ignores model sufficiency claims" do
    empty = MarketValidator.assessment(MarketValidator.new())
    refute empty.sufficient
    assert map_size(empty.data) == 11
    assert empty.model_justification == nil
    assert length(empty.missing_fields) == 10

    {:ok, agent} =
      MarketValidator.extract_fields(MarketValidator.new(), %{
        country: "Spain",
        sufficient: true,
        justification: "All information is complete."
      })

    report = MarketValidator.assessment(agent)
    refute report.sufficient
    assert report.model_justification == "All information is complete."
    refute Map.has_key?(report.data, :sufficient)
    refute Map.has_key?(report.data, :justification)
    assert report.justification =~ "Missing required answers"
  end

  test "absent diagnosis in a later text preserves prior explicit answers" do
    put_validator_backend(LanguageFakeBackend)

    {:ok, agent} =
      MarketValidator.extract_fields(MarketValidator.new(), %{
        team_size: %{status: "known", count: 3},
        digital_maturity: %{level: "unknown"}
      })

    {:ok, updated} = MarketValidator.extract_fields(agent, "first text")
    assert_receive {:backend_called, _, messages, _}
    assert updated.state.team_size == %{status: "known", count: 3, notes: nil}
    assert updated.state.digital_maturity == %{level: "unknown", evidence: nil}
    context = Enum.at(messages, 1)["content"]
    assert context =~ ~s("count":3)
    assert context =~ ~s("level":"unknown")

    assert MarketValidator.assessment(updated).missing_fields == [
             :business_market,
             :initial_budget,
             :final_product_proposal,
             :product_price,
             :current_tools_systems,
             :repetitive_processes_pain_points,
             :metrics_baselines
           ]
  end

  describe "atomic field replacement" do
    test "explicit correction replaces one collection instead of concatenating items" do
      agent = MarketValidator.new()

      # legacy-shaped fragment (e.g. rehydrated from an old persisted row):
      # string keys plus stale nested keys that no longer belong to the contract
      {:ok, agent} =
        MarketValidator.set(agent, %{
          current_tools_systems: %{
            "status" => "known",
            "items" => [%{"name" => "LegacyCRM", "extra" => "stale"}],
            "legacy_note" => "stale"
          }
        })

      # explicit correction: exactly one clean item
      {:ok, agent} =
        MarketValidator.extract_fields(agent, %{
          "current_tools_systems" => %{
            "status" => "known",
            "items" => [
              %{
                "name" => "Notion",
                "category" => "notes",
                "purpose" => "wiki",
                "integration_notes" => nil
              }
            ]
          }
        })

      expected = %{
        status: "known",
        items: [%{name: "Notion", category: "notes", purpose: "wiki", integration_notes: nil}]
      }

      # the corrected field is replaced wholesale, not merged/concatenated
      assert agent.state.current_tools_systems == expected
      assert length(agent.state.current_tools_systems.items) == 1

      # removed nested keys do not survive a correction
      refute Map.has_key?(agent.state.current_tools_systems, :legacy_note)
      refute Map.has_key?(agent.state.current_tools_systems, "items")

      # history is preserved across the rebuild
      assert [%{status: :ok, extracted: %{current_tools_systems: ^expected}}] =
               agent.state.extraction_history
    end
  end

  describe "state preservation across turns" do
    test "omitted and top-level nil values do not erase prior state" do
      {:ok, agent} =
        MarketValidator.extract_fields(MarketValidator.new(), %{
          "country" => "Spain",
          "city" => "Madrid",
          "team_size" => %{"status" => "known", "count" => 5, "notes" => "two founders"},
          "digital_maturity" => %{"level" => "manual", "evidence" => "spreadsheets"}
        })

      # next turn: only a new commercial answer; diagnosis omitted entirely,
      # city explicitly nil at top level
      {:ok, agent} =
        MarketValidator.extract_fields(agent, %{
          "business_market" => "SaaS",
          "city" => nil,
          "team_size" => nil
        })

      # new value applied
      assert agent.state.business_market == "SaaS"
      # omitted diagnosis survives untouched
      assert agent.state.team_size == %{status: "known", count: 5, notes: "two founders"}
      assert agent.state.digital_maturity == %{level: "manual", evidence: "spreadsheets"}
      # top-level nil does not erase
      assert agent.state.country == "Spain"
      assert agent.state.city == "Madrid"
    end
  end

  describe "output language capture" do
    test "first substantive text sets output_language and map input requires explicit or default language" do
      # language is wire metadata outside fields/0, covered by the schema
      schema = ExtractionOutput.schema()
      assert "output_language" in Map.keys(schema["properties"])
      assert "language_switch_requested" in Map.keys(schema["properties"])
      refute "output_language" in schema["required"]
      refute :output_language in ExtractionOutput.fields()

      put_validator_backend(LanguageFakeBackend)

      # first substantive text sets the language from the extraction answer
      {:ok, agent} = MarketValidator.extract_fields(MarketValidator.new(), "first text please")
      assert agent.state.output_language == "es"

      # a later hint without an explicit switch request never drifts
      {:ok, agent} = MarketValidator.extract_fields(agent, "silent hint follows")
      assert agent.state.output_language == "es"

      # an explicit switch request switches
      {:ok, agent} = MarketValidator.extract_fields(agent, "explicit switch to English")
      assert agent.state.output_language == "en"

      # map input: default language when no explicit key
      {:ok, agent} = MarketValidator.extract_fields(MarketValidator.new(), %{country: "Spain"})
      assert agent.state.output_language == "en"

      # map input: explicit key switches (client override)
      {:ok, agent} =
        MarketValidator.extract_fields(agent, %{"output_language" => "es", "city" => "Madrid"})

      assert agent.state.output_language == "es"

      # missing hint: no drift
      {:ok, agent} = MarketValidator.extract_fields(agent, %{business_market: "fintech"})
      assert agent.state.output_language == "es"

      # invalid hint: no drift
      {:ok, agent} =
        MarketValidator.extract_fields(agent, %{
          "output_language" => "Spanish!",
          "initial_budget" => "5000 EUR"
        })

      assert agent.state.output_language == "es"

      # owner control metadata is rejected from client extraction input
      assert {:error, {:reserved_key, :_pipeline}} =
               MarketValidator.extract_fields(MarketValidator.new(), %{
                 "_pipeline" => %{"cursor" => 1},
                 "country" => "Spain"
               })
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
