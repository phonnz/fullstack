defmodule Fullstack.JidoMarketAgents.Agents.BackendDispatchTest do
  # Mutates and restores Application.get_env(:fullstack, Fullstack.JidoMarketAgents,
  # ...), so this module must not run concurrently with other tests reading or
  # writing the same application env key (see llm_test.exs for the same rule).
  use ExUnit.Case, async: false

  alias Fullstack.JidoMarketAgents.Agents.{MarketValidator, MarketResearcher, ExtractionOutput}

  @app :fullstack
  @scope Fullstack.JidoMarketAgents

  # -- Fake backends, mirroring the llm_test.exs idiom -----------------------

  defmodule FakeBackend do
    @moduledoc false
    @behaviour Fullstack.JidoMarketAgents.LLM.Backend

    @impl true
    def chat_completion(_messages, opts) do
      response_format = Keyword.get(opts, :response_format)
      send(self(), {:backend_called, __MODULE__, response_format, opts})
      {:ok, fake_reply(response_format)}
    end

    defp fake_reply({:json_object, _schema}), do: ~s({"country":"Spain"})
    defp fake_reply(:text), do: "There are no established competitors in this market."
    defp fake_reply(_), do: "{}"

    @impl true
    def capabilities(_opts), do: [:json_object, :temperature, :max_tokens]

    @impl true
    def validate_config(_opts), do: :ok
  end

  # A second distinct module, so per-role independence can be proven by
  # asserting each role reached its *own* backend module, not merely its own
  # opts on a shared one.
  defmodule FakeValidatorBackend do
    @moduledoc false
    @behaviour Fullstack.JidoMarketAgents.LLM.Backend

    @impl true
    def chat_completion(_messages, opts) do
      send(self(), {:backend_called, __MODULE__, opts})
      {:ok, ~s({"business_market":"fintech"})}
    end

    @impl true
    def capabilities(_opts), do: [:json_object]

    @impl true
    def validate_config(_opts), do: :ok
  end

  defmodule FakeResearcherBackend do
    @moduledoc false
    @behaviour Fullstack.JidoMarketAgents.LLM.Backend

    @impl true
    def chat_completion(_messages, opts) do
      send(self(), {:backend_called, __MODULE__, opts})
      {:ok, "researcher backend reply"}
    end

    @impl true
    def capabilities(_opts), do: []

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

  defp put_backends(validator, researcher) do
    base = Application.get_env(@app, @scope, [])

    Application.put_env(
      @app,
      @scope,
      Keyword.merge(base, validator_backend: validator, researcher_backend: researcher)
    )
  end

  # -- MarketValidator dispatches through LLM with {:json_object, schema} ----

  describe "MarketValidator.extract_fields/2 (string input) dispatch" do
    test "calls LLM.chat_completion(:validator, ..., response_format: {:json_object, schema})" do
      put_backends(
        {FakeValidatorBackend, model: "v-model"},
        {FakeResearcherBackend, model: "r-model"}
      )

      assert {:ok, _agent} =
               MarketValidator.extract_fields(MarketValidator.new(), "I sell payment apps")

      assert_received {:backend_called, FakeValidatorBackend, opts}
      assert Keyword.get(opts, :response_format) == {:json_object, ExtractionOutput.schema()}
      assert Keyword.get(opts, :model) == "v-model"

      # The researcher backend is never touched by extraction.
      refute_received {:backend_called, FakeResearcherBackend, _}
    end

    test "no longer passes call-site temperature/max_tokens opts (role config owns them)" do
      put_backends(
        {FakeValidatorBackend, model: "v-model"},
        {FakeResearcherBackend, model: "r-model"}
      )

      assert {:ok, _agent} =
               MarketValidator.extract_fields(MarketValidator.new(), "any message")

      assert_received {:backend_called, FakeValidatorBackend, opts}
      # Only role-config-owned keys plus response_format should be present.
      assert Keyword.keys(opts) |> Enum.sort() == [:model, :response_format]
    end
  end

  describe "MarketResearcher.research/1 dispatch" do
    test "calls LLM.chat_completion(:researcher, ..., response_format: :text)" do
      put_backends(
        {FakeValidatorBackend, model: "v-model"},
        {FakeResearcherBackend, model: "r-model"}
      )

      agent =
        MarketResearcher.new()
        |> Map.update!(:state, fn state ->
          Map.merge(state, %{
            country: "Spain",
            city: "Madrid",
            business_market: "fintech",
            final_product_proposal: "Payment app"
          })
        end)

      assert {:ok, %{research_result: "researcher backend reply"}} =
               MarketResearcher.research(agent)

      assert_received {:backend_called, FakeResearcherBackend, opts}
      assert Keyword.get(opts, :response_format) == :text
      assert Keyword.get(opts, :model) == "r-model"

      # The validator backend is never touched by research.
      refute_received {:backend_called, FakeValidatorBackend, _}
    end

    test "no longer passes call-site max_tokens opt (role config owns it)" do
      put_backends(
        {FakeValidatorBackend, model: "v-model"},
        {FakeResearcherBackend, model: "r-model"}
      )

      agent =
        MarketResearcher.new()
        |> Map.update!(:state, fn state ->
          Map.merge(state, %{
            country: "Spain",
            city: "Madrid",
            business_market: "fintech",
            final_product_proposal: "Payment app"
          })
        end)

      assert {:ok, _} = MarketResearcher.research(agent)

      assert_received {:backend_called, FakeResearcherBackend, opts}
      assert Keyword.keys(opts) |> Enum.sort() == [:model, :response_format]
    end
  end

  # -- Per-role independence, proven at the agent seam ------------------------

  describe "per-role backend independence at the agent seam" do
    test "validator and researcher agents reach their own distinct configured backend modules" do
      put_backends(
        {FakeValidatorBackend, model: "only-validator-sees-this"},
        {FakeResearcherBackend, model: "only-researcher-sees-this"}
      )

      assert {:ok, _agent} =
               MarketValidator.extract_fields(MarketValidator.new(), "extract this")

      agent =
        MarketResearcher.new()
        |> Map.update!(:state, fn state ->
          Map.merge(state, %{
            country: "France",
            business_market: "healthtech",
            final_product_proposal: "Telehealth app"
          })
        end)

      assert {:ok, _} = MarketResearcher.research(agent)

      assert_received {:backend_called, FakeValidatorBackend, validator_opts}
      assert_received {:backend_called, FakeResearcherBackend, researcher_opts}

      assert Keyword.get(validator_opts, :model) == "only-validator-sees-this"
      assert Keyword.get(researcher_opts, :model) == "only-researcher-sees-this"
    end
  end

  # -- Accumulation across partial turns, re-proven at the LLM dispatch seam --

  describe "partial-turn accumulation through the LLM dispatch seam" do
    test "a partial LLM extraction merges into prior map-sourced state without erasing it" do
      put_backends({FakeBackend, model: "v-model"}, {FakeBackend, model: "r-model"})

      {:ok, agent} =
        MarketValidator.extract_fields(MarketValidator.new(), %{
          country: "Germany",
          city: "Berlin"
        })

      assert {:ok, agent} =
               MarketValidator.extract_fields(agent, "tell me about fintech in Berlin")

      # FakeBackend's canned validator reply only mentions "country" (later
      # value wins, per existing merge semantics), but the accumulated city
      # from the prior map turn — absent from this turn's LLM reply — must
      # survive untouched rather than being erased.
      assert agent.state.country == "Spain"
      assert agent.state.city == "Berlin"

      assert agent.state.extraction_history |> Enum.at(1) |> Map.get(:extracted) ==
               %{country: "Spain"}

      assert length(agent.state.extraction_history) == 2
    end
  end

  # -- Map fast path still makes no LLM call ----------------------------------

  describe "map fast path makes no LLM call" do
    test "extract_fields/2 with a map never reaches the configured backend" do
      put_backends({FakeBackend, model: "v-model"}, {FakeBackend, model: "r-model"})

      assert {:ok, agent} =
               MarketValidator.extract_fields(MarketValidator.new(), %{country: "Spain"})

      assert agent.state.country == "Spain"
      refute_received {:backend_called, FakeBackend, _tag, _opts}
    end
  end
end
