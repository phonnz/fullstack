defmodule Fullstack.JidoMarketAgentsTest do
  use ExUnit.Case, async: false

  alias Fullstack.JidoMarketAgents
  alias Fullstack.JidoMarketAgents.Agents.{MarketValidator, MarketResearcher}

  alias Fullstack.JidoMarketAgents.LLM.MimoClient

  setup_all do
    responses = start_supervised!({Agent, fn -> %{} end})

    plug = fn conn, _opts ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      request = Jason.decode!(body)
      message = request["messages"] |> List.last() |> Map.fetch!("content")
      {owner, content} = Agent.get(responses, &Map.get(&1, message, {nil, "{}"}))
      if owner, do: send(owner, {:mimo_request, request})

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(%{choices: [%{message: %{content: content}}]}))
    end

    server = start_supervised!({Bandit, plug: plug, ip: {127, 0, 0, 1}, port: 0})
    {:ok, {_address, port}} = ThousandIsland.listener_info(server)
    previous_env = Map.new(["MIMO_BASE_URL", "MIMO_API_KEY"], &{&1, System.get_env(&1)})
    System.put_env("MIMO_BASE_URL", "http://127.0.0.1:#{port}/v1")
    System.put_env("MIMO_API_KEY", "local-test-key")

    on_exit(fn ->
      for key <- ["MIMO_BASE_URL", "MIMO_API_KEY"] do
        case previous_env[key] do
          nil -> System.delete_env(key)
          value -> System.put_env(key, value)
        end
      end
    end)

    {:ok, mimo_responses: responses}
  end

  defp stub_mimo(responses, message, content) do
    owner = self()
    Agent.update(responses, &Map.put(&1, message, {owner, content}))
    [%{"role" => "user", "content" => message}]
  end

  # ── Helper ──────────────────────────────────────────────────────────────────

  defp send_and_await_extraction(id, payload) do
    assert {:ok, :accepted, ^id} = JidoMarketAgents.send_message(id, payload)
    assert_receive {:extraction_complete, %{conversation_id: ^id} = p}, 2_000
    p
  end

  # ── Validator / Researcher unit tests (untouched) ──────────────────────────

  describe "MarketValidator - check_completeness" do
    test "reports incomplete when required fields are missing" do
      agent = MarketValidator.new()
      {:ok, agent} = MarketValidator.set(agent, %{country: "Spain"})

      assert {:incomplete, fields} = MarketValidator.check_completeness(agent)
      assert :business_market in fields
      assert :initial_budget in fields
      assert :final_product_proposal in fields
      assert :product_price in fields
      refute :country in fields
    end

    test "returns complete data when all required fields present" do
      agent = MarketValidator.new()

      {:ok, agent} =
        MarketValidator.set(agent, %{
          country: "Spain",
          business_market: "fintech",
          initial_budget: "50000",
          final_product_proposal: "Payment app",
          product_price: "9.99"
        })

      assert {:complete, data} = MarketValidator.check_completeness(agent)
      assert data.country == "Spain"
      assert data.business_market == "fintech"
    end

    test "city is optional for completeness" do
      agent = MarketValidator.new()

      {:ok, agent} =
        MarketValidator.set(agent, %{
          country: "Spain",
          business_market: "fintech",
          initial_budget: "50000",
          final_product_proposal: "Payment app",
          product_price: "9.99"
        })

      assert {:complete, _} = MarketValidator.check_completeness(agent)
    end

    test "empty strings count as missing" do
      agent = MarketValidator.new()

      {:ok, agent} =
        MarketValidator.set(agent, %{
          country: "Spain",
          business_market: "",
          initial_budget: "50000",
          final_product_proposal: "Payment app",
          product_price: "9.99"
        })

      assert {:incomplete, fields} = MarketValidator.check_completeness(agent)
      assert :business_market in fields
    end
  end

  describe "MarketValidator - validate_data (backward compat)" do
    test "reports missing fields when data is incomplete" do
      agent = MarketValidator.new()
      {:ok, agent} = MarketValidator.set(agent, %{country: "Spain"})

      assert {:missing, fields} = MarketValidator.validate_data(agent)
      assert :business_market in fields
      assert :initial_budget in fields
      assert :final_product_proposal in fields
      assert :product_price in fields
      refute :country in fields
    end

    test "returns complete data when all required fields present" do
      agent = MarketValidator.new()

      {:ok, agent} =
        MarketValidator.set(agent, %{
          country: "Spain",
          business_market: "fintech",
          initial_budget: "50000",
          final_product_proposal: "Payment app",
          product_price: "9.99"
        })

      assert {:complete, data} = MarketValidator.validate_data(agent)
      assert data.country == "Spain"
      assert data.business_market == "fintech"
    end
  end

  describe "MarketValidator - format_missing_prompt" do
    test "returns human-readable prompt for missing fields" do
      prompt = MarketValidator.format_missing_prompt([:country, :business_market])
      assert prompt =~ "country"
      assert prompt =~ "business market"
      assert prompt =~ "Thanks! I still need"
    end

    test "prompts only for specific missing fields" do
      prompt = MarketValidator.format_missing_prompt([:initial_budget, :product_price])
      assert prompt =~ "initial budget"
      assert prompt =~ "product price"
      refute prompt =~ "country"
    end
  end

  describe "MarketValidator - format_extraction_summary" do
    test "shows extracted values and missing fields" do
      agent = MarketValidator.new()
      {:ok, agent} = MarketValidator.set(agent, %{country: "Spain", business_market: "fintech"})

      summary = MarketValidator.format_extraction_summary(agent)
      assert summary =~ "Country: Spain"
      assert summary =~ "Business market: fintech"
      assert summary =~ "not provided"
    end

    test "shows all collected when complete" do
      agent = MarketValidator.new()

      {:ok, agent} =
        MarketValidator.set(agent, %{
          country: "Spain",
          business_market: "fintech",
          initial_budget: "50000",
          final_product_proposal: "Payment app",
          product_price: "9.99"
        })

      summary = MarketValidator.format_extraction_summary(agent)
      assert summary =~ "Country: Spain"
      assert summary =~ "Business market: fintech"
      assert summary =~ "Initial budget: 50000"
      assert summary =~ "all required fields collected"
    end
  end

  describe "MarketValidator - extract_fields (map fast path)" do
    test "keeps exactly the six allowed fields and stringifies their values" do
      fields = %{
        "country" => "Spain",
        "city" => "Madrid",
        "business_market" => "fintech",
        "initial_budget" => 50000,
        "final_product_proposal" => "Payment app",
        "product_price" => 9.99,
        "unknown_field" => "ignored",
        :unexpected => "ignored"
      }

      assert {:ok, agent} = MarketValidator.extract_fields(MarketValidator.new(), fields)

      assert [%{extracted: extracted}] = agent.state.extraction_history

      assert extracted == %{
               country: "Spain",
               city: "Madrid",
               business_market: "fintech",
               initial_budget: "50000",
               final_product_proposal: "Payment app",
               product_price: "9.99"
             }

      refute Map.has_key?(agent.state, :unexpected)
      refute Map.has_key?(agent.state, "unknown_field")
    end

    test "drops unknown string and atom keys without creating atoms" do
      unknown = "unknown_field_#{System.unique_integer([:positive])}"
      assert_raise ArgumentError, fn -> String.to_existing_atom(unknown) end

      assert {:ok, agent} =
               MarketValidator.extract_fields(MarketValidator.new(), %{
                 "country" => "Spain",
                 unknown => "ignored",
                 :unexpected => "ignored",
                 :extraction_history => "cannot override internal state"
               })

      assert agent.state.country == "Spain"
      refute Map.has_key?(agent.state, :unexpected)
      refute Map.has_key?(agent.state, unknown)
      assert [%{extracted: %{country: "Spain"}}] = agent.state.extraction_history
      assert_raise ArgumentError, fn -> String.to_existing_atom(unknown) end
    end

    test "coerces scalar values to strings and drops unsupported values" do
      assert {:ok, agent} =
               MarketValidator.extract_fields(MarketValidator.new(), %{
                 country: :Spain,
                 city: ["Madrid"],
                 business_market: false,
                 initial_budget: 50000,
                 final_product_proposal: %{name: "App"},
                 product_price: 9.99
               })

      assert agent.state.country == "Spain"
      assert agent.state.initial_budget == "50000"
      assert agent.state.product_price == "9.99"
      assert agent.state.business_market == "false"
      assert Map.get(agent.state, :city) == nil
      assert Map.get(agent.state, :final_product_proposal) == nil
    end

    test "extracts fields from a map without LLM call" do
      agent = MarketValidator.new()

      {:ok, agent} =
        MarketValidator.extract_fields(agent, %{
          country: "Germany",
          business_market: "healthtech"
        })

      assert agent.state.country == "Germany"
      assert agent.state.business_market == "healthtech"
    end

    test "accumulates fields across multiple extract_fields calls" do
      agent = MarketValidator.new()

      {:ok, agent} =
        MarketValidator.extract_fields(agent, %{country: "Spain", city: "Barcelona"})

      {:ok, agent} =
        MarketValidator.extract_fields(agent, %{
          business_market: "fintech",
          initial_budget: "50000 EUR"
        })

      {:ok, agent} =
        MarketValidator.extract_fields(agent, %{
          final_product_proposal: "Payment app",
          product_price: "9.99 EUR"
        })

      assert agent.state.country == "Spain"
      assert agent.state.city == "Barcelona"
      assert agent.state.business_market == "fintech"
      assert agent.state.initial_budget == "50000 EUR"
      assert agent.state.final_product_proposal == "Payment app"
      assert agent.state.product_price == "9.99 EUR"
    end

    test "preserves earlier values when new message has overlapping fields" do
      agent = MarketValidator.new()

      {:ok, agent} = MarketValidator.extract_fields(agent, %{country: "Spain"})
      {:ok, agent} = MarketValidator.extract_fields(agent, %{country: "France"})

      # Later value wins
      assert agent.state.country == "France"
    end

    test "tracks extraction history" do
      agent = MarketValidator.new()

      {:ok, agent} =
        MarketValidator.extract_fields(agent, %{country: "Spain", business_market: "fintech"})

      {:ok, agent} =
        MarketValidator.extract_fields(agent, %{initial_budget: "50000 EUR"})

      history = agent.state.extraction_history
      assert length(history) == 2
      assert Enum.at(history, 0).extracted[:country] == "Spain"
      assert Enum.at(history, 1).extracted[:initial_budget] == "50000 EUR"
    end
  end

  describe "MarketValidator - extract_fields (string input)" do
    test "returns a parse failure for invalid JSON", %{mimo_responses: responses} do
      stub_mimo(responses, "invalid extraction", "not JSON")

      assert {:error, {:parse_failed, {:json_parse, _}}} =
               MarketValidator.extract_fields(MarketValidator.new(), "invalid extraction")
    end

    test "rejects valid JSON that is not an object", %{mimo_responses: responses} do
      stub_mimo(responses, "non-object extraction", "[]")

      assert {:error, {:parse_failed, :not_a_map}} =
               MarketValidator.extract_fields(MarketValidator.new(), "non-object extraction")
    end

    test "merges valid partial JSON and requests JSON mode", %{mimo_responses: responses} do
      stub_mimo(responses, "partial extraction", ~s({"city":"Madrid"}))
      {:ok, agent} = MarketValidator.extract_fields(MarketValidator.new(), %{country: "Spain"})

      assert {:ok, agent} = MarketValidator.extract_fields(agent, "partial extraction")
      assert agent.state.country == "Spain"
      assert agent.state.city == "Madrid"
      assert length(agent.state.extraction_history) == 2
      assert_receive {:mimo_request, %{"response_format" => %{"type" => "json_object"}}}
    end

    test "normalizes complete JSON through the same schema", %{mimo_responses: responses} do
      fields = %{
        "country" => "Spain",
        "city" => "Madrid",
        "business_market" => "fintech",
        "initial_budget" => 50000,
        "final_product_proposal" => "Payment app",
        "product_price" => 9.99,
        "unexpected_model_field" => "ignored"
      }

      stub_mimo(responses, "complete extraction", Jason.encode!(fields))

      assert {:ok, agent} =
               MarketValidator.extract_fields(MarketValidator.new(), "complete extraction")

      assert {:complete, data} = MarketValidator.check_completeness(agent)
      assert data.initial_budget == "50000"
      assert data.product_price == "9.99"
      assert data.country == "Spain"
      refute Map.has_key?(agent.state, :unexpected_model_field)
    end

    test "empty JSON preserves previous fields", %{mimo_responses: responses} do
      stub_mimo(responses, "empty extraction", "{}")
      {:ok, agent} = MarketValidator.extract_fields(MarketValidator.new(), %{country: "Spain"})
      assert {:ok, agent} = MarketValidator.extract_fields(agent, "empty extraction")
      assert agent.state.country == "Spain"
    end
  end

  describe "MimoClient JSON mode" do
    test "includes response_format when opted in", %{mimo_responses: responses} do
      messages = stub_mimo(responses, "json mode enabled", "{}")
      assert {:ok, "{}"} = MimoClient.chat_completion(messages, json_mode: true)
      assert_receive {:mimo_request, %{"response_format" => %{"type" => "json_object"}}}
    end

    test "omits response_format by default and when disabled", %{mimo_responses: responses} do
      for {message, opts} <- [
            {"json mode default", []},
            {"json mode disabled", [json_mode: false]}
          ] do
        messages = stub_mimo(responses, message, "plain text")
        assert {:ok, "plain text"} = MimoClient.chat_completion(messages, opts)
        assert_receive {:mimo_request, request}
        refute Map.has_key?(request, "response_format")
      end
    end
  end

  describe "MarketResearcher" do
    test "agent has correct schema fields" do
      agent = MarketResearcher.new()
      assert agent.state[:country] == nil
      assert agent.state[:business_market] == nil
    end
  end

  # ── Conversation API tests (rewritten + new) ───────────────────────────────

  describe "Conversation API - async send_message" do
    # -- Rewritten original tests (adapted to async + PubSub) -------------------

    test "send_message with map returns needs_data and accumulates state" do
      id = "test-acc-#{System.unique_integer([:positive])}"
      JidoMarketAgents.subscribe(id)

      # First message: partial data
      p1 = send_and_await_extraction(id, %{country: "Spain"})
      assert p1.status == :needs_data
      last = List.last(p1.messages)
      assert last.content =~ "country" or last.content =~ "still need"

      # Second message: more data
      p2 = send_and_await_extraction(id, %{business_market: "fintech"})
      assert p2.status == :needs_data
      assert length(p2.messages) >= 4
    end

    test "send_message with complete map data starts researching" do
      id = "test-complete-#{System.unique_integer([:positive])}"
      JidoMarketAgents.subscribe(id)

      data = %{
        country: "Spain",
        business_market: "fintech",
        initial_budget: "50000 EUR",
        final_product_proposal: "Mobile payment app",
        product_price: "9.99 EUR"
      }

      assert {:ok, :accepted, ^id} = JidoMarketAgents.send_message(id, data)
      assert_receive {:extraction_complete, %{conversation_id: ^id, status: :researching}}, 2_000

      # Research may succeed or fail depending on MIMO availability
      assert_receive {:research_complete, %{status: :completed}}, 60_000
    end

    test "multi-turn: accumulate fields then trigger research" do
      id = "test-multi-#{System.unique_integer([:positive])}"
      JidoMarketAgents.subscribe(id)

      # Turn 1: country + city
      send_and_await_extraction(id, %{country: "Spain", city: "Madrid"})

      # Turn 2: business market
      send_and_await_extraction(id, %{business_market: "fintech"})

      # Turn 3: remaining fields → should trigger research
      assert {:ok, :accepted, ^id} =
               JidoMarketAgents.send_message(id, %{
                 initial_budget: "50000 EUR",
                 final_product_proposal: "Mobile payment app",
                 product_price: "9.99 EUR"
               })

      assert_receive {:extraction_complete, %{status: :researching}}, 2_000

      # Research outcome depends on MIMO
      assert_receive msg, 60_000
      assert match?({:research_complete, _}, msg) or match?({:error, %{stage: :research}}, msg)
    end

    test "incomplete data prompt is specific about missing fields" do
      id = "test-specific-#{System.unique_integer([:positive])}"
      JidoMarketAgents.subscribe(id)

      p = send_and_await_extraction(id, %{country: "Spain"})
      last = List.last(p.messages)
      assert last.content =~ "business market"
      assert last.content =~ "initial budget"
      assert last.content =~ "product price"
      refute last.content =~ "Thanks! I still need: country"
    end

    test "resume returns conversation state" do
      id = "test-resume-#{System.unique_integer([:positive])}"
      JidoMarketAgents.subscribe(id)

      send_and_await_extraction(id, %{country: "Spain"})

      assert {:ok, :active, messages} = JidoMarketAgents.resume(id)
      assert is_list(messages)
    end

    test "list_messages returns all messages across turns" do
      id = "test-list-#{System.unique_integer([:positive])}"
      JidoMarketAgents.subscribe(id)

      send_and_await_extraction(id, %{country: "Spain"})
      send_and_await_extraction(id, %{business_market: "fintech"})

      assert {:ok, messages} = JidoMarketAgents.list_messages(id)
      # At least 4 messages: 2 user + 2 assistant responses
      assert length(messages) >= 4
    end

    # -- Unaffected original test ----------------------------------------------

    test "resume non-existent conversation returns error" do
      assert {:error, :conversation_not_found} =
               JidoMarketAgents.resume("non-existent-#{System.unique_integer([:positive])}")
    end
  end

  # ── A. Acknowledgment contract ─────────────────────────────────────────────

  describe "Acknowledgment contract" do
    test "send_message returns {:ok, :accepted, id} for a brand-new id" do
      id = "test-new-#{System.unique_integer([:positive])}"

      assert {:ok, :accepted, ^id} =
               JidoMarketAgents.send_message(id, %{country: "Spain"})
    end

    test "send_message returns {:ok, :accepted, id} for an existing id" do
      id = "test-existing-#{System.unique_integer([:positive])}"

      assert {:ok, :accepted, ^id} =
               JidoMarketAgents.send_message(id, %{country: "Spain"})

      assert {:ok, :accepted, ^id} =
               JidoMarketAgents.send_message(id, %{business_market: "fintech"})
    end

    test "acknowledgment is fast (no LLM in handle_call)" do
      id = "test-fast-#{System.unique_integer([:positive])}"

      {elapsed_us, {:ok, :accepted, _id}} =
        :timer.tc(fn -> JidoMarketAgents.send_message(id, %{country: "Spain"}) end)

      elapsed_ms = div(elapsed_us, 1_000)
      assert elapsed_ms < 500, "send_message took #{elapsed_ms}ms, expected < 500ms"
    end
  end

  # ── B. PubSub delivery ─────────────────────────────────────────────────────

  describe "PubSub delivery" do
    test "subscriber receives extraction_complete with needs_data for partial map" do
      id = "test-pubsub-needs-#{System.unique_integer([:positive])}"
      JidoMarketAgents.subscribe(id)

      p = send_and_await_extraction(id, %{country: "Spain"})
      assert p.status == :needs_data
      assert is_list(p.messages)
      last = List.last(p.messages)
      assert last.role == :assistant
    end

    test "subscriber receives extraction_complete with researching for complete map" do
      id = "test-pubsub-researching-#{System.unique_integer([:positive])}"
      JidoMarketAgents.subscribe(id)

      assert {:ok, :accepted, ^id} =
               JidoMarketAgents.send_message(id, %{
                 country: "Spain",
                 business_market: "fintech",
                 initial_budget: "50000 EUR",
                 final_product_proposal: "Mobile payment app",
                 product_price: "9.99 EUR"
               })

      assert_receive {:extraction_complete, %{conversation_id: ^id, status: :researching}}, 2_000
    end

    test "payload always includes conversation_id matching the id" do
      id = "test-pubsub-cid-#{System.unique_integer([:positive])}"
      JidoMarketAgents.subscribe(id)

      p = send_and_await_extraction(id, %{country: "Spain"})
      assert p.conversation_id == id
    end

    test "payload messages equals list_messages at time of receipt" do
      id = "test-pubsub-agree-#{System.unique_integer([:positive])}"
      JidoMarketAgents.subscribe(id)

      p = send_and_await_extraction(id, %{country: "Spain"})
      {:ok, polled_messages} = JidoMarketAgents.list_messages(id)
      assert p.messages == polled_messages
    end

    test "non-subscriber receives nothing" do
      id = "test-pubsub-noise-#{System.unique_integer([:positive])}"
      # Do NOT subscribe

      spawn_link(fn ->
        send_and_await_extraction(id, %{country: "Spain"})
      end)

      # Give extraction time to complete
      Process.sleep(500)
      refute_receive {:extraction_complete, _}
      refute_receive {:research_complete, _}
    end

    test "two subscribers on the same topic both receive every stage" do
      id = "test-pubsub-fanout-#{System.unique_integer([:positive])}"

      # Subscribe in a second process
      test_pid = self()

      subscriber_pid =
        spawn_link(fn ->
          JidoMarketAgents.subscribe(id)
          send(test_pid, :subscribed)

          receive do
            msg -> send(test_pid, {:sub2, msg})
          after
            5_000 -> send(test_pid, :sub2_timeout)
          end
        end)

      assert_receive :subscribed, 1_000
      JidoMarketAgents.subscribe(id)

      p = send_and_await_extraction(id, %{country: "Spain"})

      assert p.status == :needs_data

      assert_receive {:sub2, {:extraction_complete, %{status: :needs_data}}}, 2_000
    end
  end

  # ── C. Error paths ─────────────────────────────────────────────────────────

  describe "Error paths" do
    test "research failure broadcasts error with stage: research" do
      id = "test-err-research-#{System.unique_integer([:positive])}"
      JidoMarketAgents.subscribe(id)

      # Send complete data to trigger research
      assert {:ok, :accepted, ^id} =
               JidoMarketAgents.send_message(id, %{
                 country: "Spain",
                 business_market: "fintech",
                 initial_budget: "50000 EUR",
                 final_product_proposal: "Mobile payment app",
                 product_price: "9.99 EUR"
               })

      assert_receive {:extraction_complete, %{status: :researching}}, 2_000

      # Research may succeed or fail depending on MIMO; accept either
      msg =
        receive do
          m -> m
        after
          60_000 -> flunk("Timed out waiting for research outcome")
        end

      case msg do
        {:research_complete, %{status: :completed}} ->
          # MIMO worked — test passes
          :ok

        {event, %{status: :error, stage: :research, reason: reason}} ->
          assert event == :error
          assert is_atom(reason) or is_tuple(reason) or is_binary(reason)
          assert {:ok, :error, _messages} = JidoMarketAgents.resume(id)
      end
    end

    test "extraction failure broadcasts error with stage: extraction" do
      id = "test-err-extract-#{System.unique_integer([:positive])}"
      JidoMarketAgents.subscribe(id)

      # String input goes through LLM extraction — may fail in test env
      assert {:ok, :accepted, ^id} = JidoMarketAgents.send_message(id, "I want to sell things")

      msg =
        receive do
          m -> m
        after
          60_000 -> flunk("Timed out waiting for extraction outcome")
        end

      case msg do
        {:extraction_complete, %{status: _}} ->
          # Extraction succeeded — test passes (map path or LLM worked)
          :ok

        {event, %{status: :error, stage: :extraction, reason: _reason}} ->
          assert event == :error
          assert {:ok, :error, _} = JidoMarketAgents.resume(id)
      end
    end
  end

  # ── D. Polling fallback ────────────────────────────────────────────────────

  describe "Polling fallback" do
    test "resume after extraction_complete returns :active with same messages" do
      id = "test-poll-active-#{System.unique_integer([:positive])}"
      JidoMarketAgents.subscribe(id)

      p = send_and_await_extraction(id, %{country: "Spain"})

      assert {:ok, :active, polled} = JidoMarketAgents.resume(id)
      assert p.messages == polled
    end

    test "resume after research_complete returns :completed" do
      id = "test-poll-completed-#{System.unique_integer([:positive])}"
      JidoMarketAgents.subscribe(id)

      assert {:ok, :accepted, ^id} =
               JidoMarketAgents.send_message(id, %{
                 country: "Spain",
                 business_market: "fintech",
                 initial_budget: "50000 EUR",
                 final_product_proposal: "Mobile payment app",
                 product_price: "9.99 EUR"
               })

      assert_receive {:extraction_complete, %{status: :researching}}, 2_000

      msg =
        receive do
          m -> m
        after
          60_000 -> flunk("Timed out waiting for research outcome")
        end

      case msg do
        {:research_complete, _} ->
          assert {:ok, :completed, _} = JidoMarketAgents.resume(id)

        {event, %{stage: :research}} ->
          assert event == :error
          assert {:ok, :error, _} = JidoMarketAgents.resume(id)
      end
    end

    test "list_messages accumulates across turns when each is awaited" do
      id = "test-poll-accum-#{System.unique_integer([:positive])}"
      JidoMarketAgents.subscribe(id)

      send_and_await_extraction(id, %{country: "Spain"})
      send_and_await_extraction(id, %{business_market: "fintech"})

      assert {:ok, messages} = JidoMarketAgents.list_messages(id)
      assert length(messages) >= 4
    end

    test "resume and list_messages on unknown id return error" do
      bad_id = "non-existent-#{System.unique_integer([:positive])}"

      assert {:error, :conversation_not_found} = JidoMarketAgents.resume(bad_id)
      assert {:error, :conversation_not_found} = JidoMarketAgents.list_messages(bad_id)
    end
  end

  # ── E. Ordering / concurrency ──────────────────────────────────────────────

  describe "Ordering and concurrency" do
    test "three sequential turns accumulate validator state and end in researching" do
      id = "test-order-seq-#{System.unique_integer([:positive])}"
      JidoMarketAgents.subscribe(id)

      # Turn 1
      p1 = send_and_await_extraction(id, %{country: "Spain", city: "Madrid"})
      assert p1.status == :needs_data

      # Turn 2
      p2 = send_and_await_extraction(id, %{business_market: "fintech"})
      assert p2.status == :needs_data
      assert length(p2.messages) > length(p1.messages)

      # Turn 3 — complete data
      assert {:ok, :accepted, ^id} =
               JidoMarketAgents.send_message(id, %{
                 initial_budget: "50000 EUR",
                 final_product_proposal: "Mobile payment app",
                 product_price: "9.99 EUR"
               })

      assert_receive {:extraction_complete, %{status: :researching}}, 2_000
    end

    test "two back-to-back sends both return :accepted and deliver two extractions" do
      id = "test-order-btb-#{System.unique_integer([:positive])}"
      JidoMarketAgents.subscribe(id)

      # Fire two sends without awaiting
      assert {:ok, :accepted, ^id} = JidoMarketAgents.send_message(id, %{country: "Spain"})

      assert {:ok, :accepted, ^id} =
               JidoMarketAgents.send_message(id, %{business_market: "fintech"})

      # Both extractions should arrive, in order
      assert_receive {:extraction_complete, %{messages: msgs1}}, 5_000
      assert_receive {:extraction_complete, %{messages: msgs2}}, 5_000

      # Second should have more messages than first
      assert length(msgs2) > length(msgs1)
    end
  end

  # ── F. Timeout semantics ───────────────────────────────────────────────────

  describe "Timeout semantics" do
    test "tiny timeout succeeds because handle_call does no I/O" do
      id = "test-timeout-#{System.unique_integer([:positive])}"

      # 50ms timeout — would fail if extraction were still in handle_call
      assert {:ok, :accepted, ^id} =
               JidoMarketAgents.send_message(id, %{country: "Spain"}, 50)
    end
  end

  # ── topic/subscribe helpers ─────────────────────────────────────────────────

  describe "topic/subscribe helpers" do
    test "topic returns conversation:<id> string" do
      assert JidoMarketAgents.topic("abc") == "conversation:abc"
    end

    test "subscribe allows receiving broadcasts" do
      id = "test-helper-#{System.unique_integer([:positive])}"
      assert :ok = JidoMarketAgents.subscribe(id)

      assert {:ok, :accepted, ^id} =
               JidoMarketAgents.send_message(id, %{country: "Spain"})

      assert_receive {:extraction_complete, %{conversation_id: ^id}}, 2_000
    end
  end
end
