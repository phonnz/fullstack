defmodule Fullstack.JidoMarketAgents.ConversationRehydrationTest do
  @moduledoc """
  T4: rehydration of the `Conversation` GenServer from Postgres after its
  process dies (R5 / S5.1, S5.2, S5.3).

  Runs with the Ecto sandbox in shared mode (`async: false`) — same
  reasoning as `ConversationPersistenceTest`: the `Conversation` GenServer
  is started by a `DynamicSupervisor`, not by the test process, so it does
  not own the sandbox connection on its own.

  Id scheme (T4 design decision): the GenServer's conversation `id` is the
  persisted `Conversations.Record`'s own `binary_id`. Callers create the
  `Record` first via `Conversations.create/1` and then start/ensure the
  GenServer with that `record.id` as `id`. This makes
  `Conversations.get_for_user(id, user_id)` directly usable as the
  rehydration lookup (design D8: user-scoped, no unscoped getter) with no
  schema change — consistent with spec S2.2 ("the Registry key is that
  UUID string").
  """
  use Fullstack.DataCase, async: false

  import Fullstack.AccountsFixtures

  alias Fullstack.JidoMarketAgents.Conversation
  alias Fullstack.JidoMarketAgents.Conversations

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

  test "restoration maps new statuses without dynamic atoms" do
    user = user_fixture()

    for {status, expected} <- [
          {"analyzing", :analyzing},
          {"building_strategy", :building_strategy}
        ] do
      {:ok, record} = Conversations.create(user.id)

      Repo.update_all(from(r in Conversations.Record, where: r.id == ^record.id),
        set: [status: status]
      )

      {:ok, pid} = Conversation.ensure_started(record.id, user.id)
      assert :sys.get_state(pid).status == expected
    end

    unknown = "unknown_" <> Ecto.UUID.generate()
    {:ok, record} = Conversations.create(user.id)

    Repo.update_all(from(r in Conversations.Record, where: r.id == ^record.id),
      set: [status: unknown]
    )

    assert_raise ArgumentError, fn -> String.to_existing_atom(unknown) end
    {:ok, pid} = Conversation.ensure_started(record.id, user.id)
    assert :sys.get_state(pid).status == :active
    assert_raise ArgumentError, fn -> String.to_existing_atom(unknown) end
  end

  test "restoration keeps terminal error manual and legacy precedence with closed control mappings" do
    user = user_fixture()

    for {status, control, expected_status, mode, stage} <- [
          {"error", %{"mode" => "manual", "pending_stage" => "analysis"}, :error, :manual,
           :analysis},
          {"analyzing", %{"mode" => "manual", "pending_stage" => "systems"}, :active, :manual,
           :systems},
          {"completed", nil, :completed, :legacy, nil},
          {"completed", %{"mode" => "manual", "pending_stage" => nil}, :completed, :manual, nil},
          {"building_strategy", %{"mode" => "automatic", "pending_stage" => "tech_strategy"},
           :building_strategy, :automatic, :tech_strategy},
          {"researching", %{"mode" => "unknown-mode", "pending_stage" => "unknown-stage"},
           :active, :manual, nil}
        ] do
      {:ok, record} =
        Conversations.create(user.id, %{
          status: status,
          validated_data: if(control, do: %{"_pipeline" => control}, else: nil)
        })

      {:ok, pid} = Conversation.ensure_started(record.id, user.id)
      state = :sys.get_state(pid)
      assert state.status == expected_status
      assert state.mode == mode
      assert state.pending_stage == stage
      refute_received {:mimo_request, _}
    end
  end

  # A fresh persisted `Record` whose own id is used as the GenServer id
  # (see moduledoc for the id-scheme rationale).
  defp new_persisted_id(user) do
    {:ok, record} = Conversations.create(user.id)
    record.id
  end

  # A *live* map-input user message keeps its raw map as `content`; a
  # *restored* one carries whatever string was persisted (non-binary
  # content is stringified via `inspect/1` before storing) — match on
  # either shape.
  defp user_message_matches?(message, key, value) do
    message.role == :user and
      (match?(%{^key => ^value}, message.content) or
         (is_binary(message.content) and message.content =~ to_string(value)))
  end

  # The `Conversation` child spec is the `use GenServer` default
  # (`restart: :permanent`), so `ConversationSupervisor` (`:one_for_one`)
  # automatically restarts a killed conversation under the same `id` —
  # the restart itself is what exercises rehydration (`init/1` runs again
  # with the same `opts`, including `user_id`, that `start_child` was
  # originally called with). So after killing, we wait deterministically
  # for the Registry to hold a *new*, different pid for `id` (the
  # supervisor's automatic respawn), rather than calling `ensure_started`
  # again ourselves — a manual call would race the supervisor's own
  # restart and can observe `{:error, {:already_started, pid}}`.
  defp kill_and_await_restart(id, old_pid, timeout \\ 2_000) do
    ref = Process.monitor(old_pid)
    Process.exit(old_pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^old_pid, :killed}, timeout

    deadline = System.monotonic_time(:millisecond) + timeout
    await_new_pid(id, old_pid, deadline)
  end

  defp await_new_pid(id, old_pid, deadline) do
    case Registry.lookup(Fullstack.JidoMarketAgents.ConversationRegistry, id) do
      [{^old_pid, _}] ->
        retry_or_flunk(id, old_pid, deadline)

      [] ->
        retry_or_flunk(id, old_pid, deadline)

      [{new_pid, _}] ->
        {:ok, new_pid}
    end
  end

  defp retry_or_flunk(id, old_pid, deadline) do
    if System.monotonic_time(:millisecond) >= deadline do
      flunk("timed out waiting for #{id} to be restarted by the supervisor")
    else
      Process.sleep(10)
      await_new_pid(id, old_pid, deadline)
    end
  end

  # ── S5.1: messages survive a kill and rehydrate in order ───────────────────

  describe "S5.1: message history survives process death" do
    test "prior messages are intact and the new one is appended after them" do
      user = user_fixture()
      id = new_persisted_id(user)

      {:ok, pid} = Conversation.ensure_started(id, user.id)
      Conversation.subscribe(id)

      assert {:ok, :accepted, ^id} = Conversation.send_message(id, %{country: "Spain"})
      assert_receive {:extraction_complete, %{conversation_id: ^id, status: :needs_data}}, 2_000

      {:ok, pid2} = kill_and_await_restart(id, pid)
      Conversation.subscribe(id)

      assert {:ok, :accepted, ^id} = Conversation.send_message(id, %{business_market: "fintech"})
      assert_receive {:extraction_complete, %{conversation_id: ^id} = payload}, 2_000

      assert Process.alive?(pid2)

      # The restored history (user msg + assistant follow-up) is present,
      # and the new user message is appended after it, not into an empty
      # history. A *live* map-input user message keeps its raw map as
      # `content` (see `MarketValidator.extract_fields/2`'s map fast
      # path); a *restored* one carries whatever string was persisted
      # (`persist_message/1` stringifies non-binary content via
      # `inspect/1` before storing) — so match on either shape.
      assert Enum.any?(payload.messages, &user_message_matches?(&1, :country, "Spain"))

      assert Enum.any?(
               payload.messages,
               &user_message_matches?(&1, :business_market, "fintech")
             )

      # Ordering: the pre-kill user message precedes the post-kill one.
      spain_index =
        Enum.find_index(payload.messages, &user_message_matches?(&1, :country, "Spain"))

      fintech_index =
        Enum.find_index(
          payload.messages,
          &user_message_matches?(&1, :business_market, "fintech")
        )

      assert spain_index < fintech_index
    end
  end

  # ── S5.2: partial validated_data survives rehydration (the critical case) ──

  describe "S5.2: partial extraction survives rehydration" do
    test "supplying only the remaining fields after rehydration is sufficient to complete extraction" do
      user = user_fixture()
      id = new_persisted_id(user)

      {:ok, pid} = Conversation.ensure_started(id, user.id)
      Conversation.subscribe(id)

      # Turn 1: give country only.
      assert {:ok, :accepted, ^id} = Conversation.send_message(id, %{country: "Spain"})
      assert_receive {:extraction_complete, %{conversation_id: ^id, status: :needs_data}}, 2_000

      # Turn 2: give business_market only.
      assert {:ok, :accepted, ^id} = Conversation.send_message(id, %{business_market: "fintech"})
      assert_receive {:extraction_complete, %{conversation_id: ^id, status: :needs_data}}, 2_000

      {:ok, _pid2} = kill_and_await_restart(id, pid)
      Conversation.subscribe(id)

      # Turn 3, post-rehydration: give ONLY the remaining required fields
      # (the diagnosis contract now requires explicit diagnosis answers
      # too). If country/business_market had been lost, completeness would
      # fail and this would come back as :needs_data instead of :researching.
      assert {:ok, :accepted, ^id} =
               Conversation.send_message(id, %{
                 initial_budget: "50000 EUR",
                 final_product_proposal: "Mobile payment app",
                 product_price: "9.99 EUR",
                 team_size: %{status: "unknown", count: nil, notes: nil},
                 current_tools_systems: %{status: "unknown", items: []},
                 repetitive_processes_pain_points: %{status: "unknown", items: []},
                 digital_maturity: %{level: "unknown", evidence: nil},
                 metrics_baselines: %{status: "unknown", items: []}
               })

      assert_receive {:extraction_complete, %{conversation_id: ^id, status: :researching}},
                     2_000
    end
  end

  # ── S5.3: an id with no persisted row starts fresh empty ───────────────────

  describe "S5.3: no persisted row starts fresh" do
    test "an id never persisted starts a fresh empty conversation" do
      user = user_fixture()
      # A well-formed `binary_id` under the chosen id scheme, but one for
      # which no `Record` was ever created — a genuine miss, not a
      # malformed id.
      id = Ecto.UUID.generate()

      {:ok, _pid} = Conversation.ensure_started(id, user.id)

      assert {:ok, []} = Conversation.list_messages(id)
    end
  end

  # ── Legacy six-field rows (pre-diagnosis contract) ──────────────────────────

  describe "legacy six-field validated_data rows" do
    test "pre-existing six-field row restores then waits for missing diagnosis" do
      user = user_fixture()
      {:ok, created} = Conversations.create(user.id)
      id = created.id

      # A row persisted BEFORE the diagnosis contract existed: exactly the
      # old six flat fields, all complete (it used to qualify as complete).
      legacy = %{
        "country" => "Spain",
        "city" => "Madrid",
        "business_market" => "fintech",
        "initial_budget" => "50000 EUR",
        "final_product_proposal" => "Mobile payment app",
        "product_price" => "9.99 EUR"
      }

      {:ok, record} =
        Conversations.update_state(created, %{
          status: "completed",
          validated_data: legacy
        })

      assert record.validated_data == legacy

      # Read-only attachment: restores without a crash and without any
      # provider work.
      {:ok, pid} = Conversation.ensure_started(id, user.id)
      assert Process.alive?(pid)
      Conversation.subscribe(id)

      assert {:ok, _messages} = Conversation.list_messages(id)
      assert {:ok, :completed, _messages} = Conversation.resume(id)
      refute_received {:mimo_request, _}

      # Explicit execution requalifies the diagnosis contract: the legacy
      # six fields must NOT produce false completeness — the conversation
      # waits for the missing diagnosis answers.
      assert {:ok, :accepted, ^id} = Conversation.send_message(id, %{country: "Spain"})

      assert_receive {:extraction_complete,
                      %{conversation_id: ^id, status: :needs_data} = payload},
                     2_000

      follow_up = List.last(payload.messages)
      assert follow_up.role == :assistant
      # The follow-up requests the missing diagnosis answers explicitly
      assert follow_up.content =~
               "I still need: team size, current tools and systems, repetitive processes and pain points, digital maturity, baseline metrics"

      # Explicit execution #2: a full diagnosis answer requalifies the
      # legacy row as complete.
      diagnosis = %{
        team_size: %{status: "unknown", count: nil, notes: nil},
        current_tools_systems: %{status: "unknown", items: []},
        repetitive_processes_pain_points: %{status: "unknown", items: []},
        digital_maturity: %{level: "unknown", evidence: nil},
        metrics_baselines: %{status: "unknown", items: []}
      }

      assert {:ok, :accepted, ^id} = Conversation.send_message(id, diagnosis)

      assert_receive {:extraction_complete, %{conversation_id: ^id, status: :researching}}, 2_000

      # The requalified diagnosis answers survive another process death:
      # the next turn must not re-ask for them.
      {:ok, pid2} = kill_and_await_restart(id, pid)
      assert Process.alive?(pid2)
      Conversation.subscribe(id)

      assert {:ok, :accepted, ^id} = Conversation.send_message(id, %{country: "Spain"})

      assert_receive {:extraction_complete, %{conversation_id: ^id, status: :researching}}, 2_000
    end
  end

  # ── Output language durability (system control metadata) ───────────────────

  describe "output language durability" do
    test "output_language survives conversation restart" do
      user = user_fixture()
      id = new_persisted_id(user)
      {:ok, pid} = Conversation.ensure_started(id, user.id)
      Conversation.subscribe(id)

      # Turn 1: explicit client language override
      assert {:ok, :accepted, ^id} =
               Conversation.send_message(id, %{"output_language" => "es", country: "Spain"})

      assert_receive {:extraction_complete, %{conversation_id: ^id} = payload}, 2_000
      assert payload.output_language == "es"

      # durable: persisted as system control metadata, outside the
      # user-editable business fields
      record = Conversations.get_for_user(id, user.id)
      assert record.validated_data["_pipeline"]["output_language"] == "es"

      {:ok, _pid2} = kill_and_await_restart(id, pid)
      Conversation.subscribe(id)

      # Turn 2: no language input at all — the restored language must not
      # silently drift back to the default.
      assert {:ok, :accepted, ^id} = Conversation.send_message(id, %{business_market: "fintech"})

      assert_receive {:extraction_complete, %{conversation_id: ^id} = payload}, 2_000
      assert payload.output_language == "es"
    end
  end

  # ── P54: downstream agents rebuilt from persisted result maps ──────────────

  # A persisted result map as `persist_stage_transition` writes it: JSON-ish
  # string keys plus the reserved `"_meta"` envelope.
  defp persisted_analysis do
    %{
      "viable_offer" => nil,
      "evidence" => [],
      "blocker" => "Demand unknown",
      "experiment" => "Interview buyers",
      "stale_note" => "must not survive normalization",
      "_meta" => %{"stage" => "analysis", "boundary_version" => 3}
    }
  end

  defp persisted_systems do
    base = %{
      "current_state" => "Needs work",
      "priority" => "high",
      "actions" => ["Act"],
      "kpis" => ["Leads"],
      "pitfall" => "Skip nothing"
    }

    systems =
      Map.new(
        [:acquisition, :authority, :conversion, :delivery_retention, :referrals, :information],
        &{to_string(&1), base}
      )

    systems =
      systems
      |> Map.put(
        "authority",
        Map.put(base, "layers", %{
          "personal_discourse" => "Discourse",
          "third_party_endorsement" => "Endorse",
          "success_cases" => "Cases"
        })
      )
      |> Map.put(
        "conversion",
        Map.put(base, "phases", %{
          "qualification" => "Qualify",
          "education_nurturing" => "Educate",
          "proposal" => "Propose",
          "close" => "Close"
        })
      )
      |> Map.put(
        "information",
        base
        |> Map.put("kpis", ["Leads", "Conversion", "Retention"])
        |> Map.put("upward_information_flow", %{
          "channel" => "Weekly",
          "incentive" => "Ack",
          "review_cadence" => "Weekly"
        })
      )

    %{
      "systems" => systems,
      "sequencing" => [
        "acquisition",
        "authority",
        "conversion",
        "delivery_retention",
        "referrals",
        "information"
      ],
      "quarterly_focus" => "Improve acquisition",
      "_meta" => %{"stage" => "systems", "boundary_version" => 4}
    }
  end

  describe "analysis agents rebuild from persisted result maps" do
    test "rehydration reconstructs all agents with new/1 and set/2" do
      user = user_fixture()
      {:ok, created} = Conversations.create(user.id)
      id = created.id

      facts = %{
        "country" => "Spain",
        "city" => "Madrid",
        "business_market" => "fintech",
        "initial_budget" => "50000 EUR",
        "final_product_proposal" => "Payment app",
        "product_price" => "10 EUR",
        "team_size" => %{"status" => "unknown", "count" => nil, "notes" => nil},
        "current_tools_systems" => %{"status" => "unknown", "items" => []},
        "repetitive_processes_pain_points" => %{"status" => "unknown", "items" => []},
        "digital_maturity" => %{"level" => "unknown", "evidence" => nil},
        "metrics_baselines" => %{"status" => "unknown", "items" => []}
      }

      research_fp =
        Conversation.fingerprint(:research, %{validated_data: facts, output_language: nil})

      research = %{
        "market_evidence" => [],
        "market_gaps" => [],
        "demand_signals" => [],
        "sources" => [],
        "limitations" => ["No retrieval"],
        "_meta" => %{
          "stage" => "research",
          "contract_version" => "market-research/1",
          "input_fingerprint" => research_fp,
          "boundary_version" => 2
        }
      }

      {:ok, record} =
        Conversations.update_state(created, %{
          status: "building_strategy",
          validated_data: facts,
          business_analysis: persisted_analysis(),
          systems_strategy: persisted_systems()
        })

      {:ok, _message} =
        Conversations.append_message(id, %{
          role: "assistant",
          content: "research",
          metadata: %{"type" => "market_research", "result" => research}
        })

      {:ok, pid} = Conversation.ensure_started(record.id, user.id)
      state = :sys.get_state(pid)

      # Every agent is a live `%Jido.Agent{}` rebuilt through `new/1` + `set/2`
      # from maps — never a deserialized struct.
      alias Fullstack.JidoMarketAgents.Agents

      assert state.validator_agent.agent_module == Agents.MarketValidator
      assert state.researcher_agent.agent_module == Agents.MarketResearcher
      assert state.analyzer_agent.agent_module == Agents.BusinessAnalyzer
      assert state.systems_agent.agent_module == Agents.SystemsAgent
      assert state.strategy_agent.agent_module == Agents.StrategyAgent

      # Full normalized replacement maps: `"_meta"` and stale extra keys
      # must not survive into agent state.
      assert state.analyzer_agent.state.research_output == %{
               market_evidence: [],
               market_gaps: [],
               demand_signals: [],
               sources: [],
               limitations: ["No retrieval"]
             }

      assert state.analyzer_agent.state.validated_data.country == "Spain"

      assert state.analyzer_agent.state.validated_data.team_size == %{
               status: "unknown",
               count: nil,
               notes: nil
             }

      assert state.systems_agent.state.analysis_output == %{
               viable_offer: nil,
               evidence: [],
               blocker: "Demand unknown",
               experiment: "Interview buyers"
             }

      assert state.strategy_agent.state.analysis_output == %{
               viable_offer: nil,
               evidence: [],
               blocker: "Demand unknown",
               experiment: "Interview buyers"
             }

      assert state.strategy_agent.state.systems_output.quarterly_focus == "Improve acquisition"

      assert state.strategy_agent.state.systems_output.sequencing == [
               "acquisition",
               "authority",
               "conversion",
               "delivery_retention",
               "referrals",
               "information"
             ]

      assert state.strategy_agent.state.systems_output.systems.acquisition == %{
               current_state: "Needs work",
               priority: "high",
               actions: ["Act"],
               kpis: ["Leads"],
               pitfall: "Skip nothing"
             }
    end
  end

  # ── P55: durable research selection from typed messages ────────────────────

  describe "durable research selection" do
    test "rehydration selects latest successful matching research message" do
      user = user_fixture()
      {:ok, created} = Conversations.create(user.id)
      id = created.id
      facts = %{"country" => "Spain", "business_market" => "fintech"}

      expected =
        Conversation.fingerprint(:research, %{validated_data: facts, output_language: nil})

      stale = String.duplicate("0", 64)

      research_result = fn tag, boundary ->
        %{
          "market_evidence" => [],
          "market_gaps" => [],
          "demand_signals" => [],
          "sources" => [],
          "limitations" => [tag],
          "_meta" => %{
            "stage" => "research",
            "contract_version" => "market-research/1",
            "input_fingerprint" => expected,
            "boundary_version" => boundary
          }
        }
      end

      winner = research_result.("winner", 1)
      tie_lo = research_result.("tie_lo", 2)
      tie_hi = research_result.("tie_hi", 3)
      foreign = put_in(research_result.("foreign", 6), ["_meta", "stage"], "analysis")

      unsupported =
        put_in(
          research_result.("unsupported", 7),
          ["_meta", "contract_version"],
          "market-research/9"
        )

      superseded =
        put_in(research_result.("superseded", 9), ["_meta", "input_fingerprint"], stale)

      {:ok, record} = Conversations.update_state(created, %{validated_data: facts})

      seeded =
        for {tag, result} <- [
              {"foreign", foreign},
              {"unsupported", unsupported},
              {"superseded", superseded},
              {"tie_lo", tie_lo},
              {"tie_hi", tie_hi},
              {"winner", winner}
            ] do
          {:ok, message} =
            Conversations.append_message(id, %{
              role: "assistant",
              content: tag,
              metadata: %{"type" => "market_research", "result" => result}
            })

          message
        end

      [foreign_m, unsupported_m, superseded_m, tie_lo_m, tie_hi_m, winner_m] = seeded
      base = ~N[2026-01-01 10:00:00]

      for {message, offset} <- [
            {tie_lo_m, 0},
            {tie_hi_m, 0},
            {winner_m, 1},
            {foreign_m, 2},
            {unsupported_m, 2},
            {superseded_m, 3}
          ] do
        Repo.update_all(from(m in Conversations.Message, where: m.id == ^message.id),
          set: [inserted_at: NaiveDateTime.add(base, offset, :second)]
        )
      end

      {:ok, pid} = Conversation.ensure_started(record.id, user.id)
      state = :sys.get_state(pid)
      assert state.results[:research] == winner

      # Tied timestamps resolve by durable boundary sequence, never by list
      # insertion order: the boundary winner is FIRST in this list.
      as_message = fn result, timestamp ->
        %{metadata: %{"type" => "market_research", "result" => result}, timestamp: timestamp}
      end

      assert Conversation.select_research_message(
               [as_message.(tie_hi, base), as_message.(tie_lo, base)],
               expected
             ) == tie_hi

      assert Conversation.select_research_message([as_message.(superseded, base)], expected) ==
               nil
    end
  end

  # ── P56: resume decision over durable boundaries ───────────────────────────

  defp complete_facts do
    %{
      "country" => "Spain",
      "city" => "Madrid",
      "business_market" => "fintech",
      "initial_budget" => "50000 EUR",
      "final_product_proposal" => "Payment app",
      "product_price" => "10 EUR",
      "team_size" => %{"status" => "unknown", "count" => nil, "notes" => nil},
      "current_tools_systems" => %{"status" => "unknown", "items" => []},
      "repetitive_processes_pain_points" => %{"status" => "unknown", "items" => []},
      "digital_maturity" => %{"level" => "unknown", "evidence" => nil},
      "metrics_baselines" => %{"status" => "unknown", "items" => []}
    }
  end

  defp research_boundary(facts, tag) do
    %{
      "market_evidence" => [],
      "market_gaps" => [],
      "demand_signals" => [],
      "sources" => [],
      "limitations" => [tag],
      "_meta" => %{
        "stage" => "research",
        "contract_version" => "market-research/1",
        "input_fingerprint" =>
          Conversation.fingerprint(:research, %{validated_data: facts, output_language: nil}),
        "boundary_version" => 1
      }
    }
  end

  defp resume_state(user, attrs, research) do
    {:ok, created} = Conversations.create(user.id)

    {:ok, record} = Conversations.update_state(created, attrs)

    if research do
      {:ok, _} =
        Conversations.append_message(record.id, %{
          role: "assistant",
          content: "research",
          metadata: %{"type" => "market_research", "result" => research}
        })
    end

    {:ok, pid} = Conversation.ensure_started(record.id, user.id)
    :sys.get_state(pid)
  end

  describe "resume decision table" do
    test "resume decision follows partial validation through completed strategy" do
      user = user_fixture()
      facts = complete_facts()
      research = research_boundary(facts, "durable")

      analysis_column =
        Map.put(persisted_analysis(), "_meta", %{
          "input_fingerprint" =>
            Conversation.fingerprint(:analysis, %{
              validated_data: facts,
              research_output: research,
              output_language: nil
            })
        })

      systems_column =
        Map.put(persisted_systems(), "_meta", %{
          "input_fingerprint" =>
            Conversation.fingerprint(:systems, %{
              validated_data: facts,
              research_output: research,
              analysis_output: analysis_column,
              output_language: nil
            })
        })

      tech_column = %{
        "_meta" => %{
          "input_fingerprint" =>
            Conversation.fingerprint(:tech_strategy, %{
              validated_data: facts,
              research_output: research,
              analysis_output: analysis_column,
              systems_output: systems_column,
              output_language: nil
            })
        }
      }

      # The six durable boundaries: partial validation through completed
      # strategy, each resuming at the highest contiguous valid boundary.
      boundaries = [
        {%{validated_data: %{"country" => "Spain"}}, nil, %{}, :wait},
        {%{validated_data: facts}, nil, %{}, {:run, :research}},
        {%{validated_data: facts}, research, %{}, {:run, :analysis}},
        {%{validated_data: facts}, research, %{business_analysis: analysis_column},
         {:run, :systems}},
        {%{validated_data: facts}, research,
         %{business_analysis: analysis_column, systems_strategy: systems_column},
         {:run, :tech_strategy}},
        {%{validated_data: facts}, research,
         %{
           business_analysis: analysis_column,
           systems_strategy: systems_column,
           tech_strategy: tech_column
         }, :complete}
      ]

      for {attrs, staged_research, columns, expected} <- boundaries do
        state = resume_state(user, Map.merge(attrs, columns), staged_research)
        assert Conversation.resume_point(state) == expected
      end

      # Error rows never auto-retry.
      assert Conversation.resume_point(
               resume_state(user, %{validated_data: facts, status: "error"}, research)
             ) ==
               :halt

      # Manual mode never auto-advances.
      manual_facts = Map.put(facts, "_pipeline", %{"mode" => "manual"})

      assert Conversation.resume_point(
               resume_state(user, %{validated_data: manual_facts, status: "active"}, research)
             ) == :idle

      # Read-only attachment of legacy completed rows schedules no LLM work.
      legacy =
        Map.take(facts, [
          "country",
          "city",
          "business_market",
          "initial_budget",
          "final_product_proposal",
          "product_price"
        ])

      assert Conversation.resume_point(
               resume_state(user, %{validated_data: legacy, status: "completed"}, nil)
             ) ==
               :idle

      # Fingerprint gaps are stale: a systems map with no compatible
      # analysis chain resumes at the earliest invalid boundary.
      assert Conversation.resume_point(
               resume_state(
                 user,
                 %{validated_data: facts, systems_strategy: systems_column},
                 research
               )
             ) == {:run, :analysis}

      stale_analysis =
        Map.put(persisted_analysis(), "_meta", %{"input_fingerprint" => String.duplicate("0", 64)})

      assert Conversation.resume_point(
               resume_state(
                 user,
                 %{validated_data: facts, business_analysis: stale_analysis},
                 research
               )
             ) == {:run, :analysis}
    end
  end

  # ── P58: commit-before-broadcast crash recovery ────────────────────────────

  defmodule BlockingProbeBackend do
    @behaviour Fullstack.JidoMarketAgents.LLM.Backend
    def capabilities(_), do: [:json_object]
    def validate_config(_), do: :ok

    def chat_completion(messages, opts) do
      send(opts[:owner], {:provider, opts[:model], messages})

      receive do
        {:reply, result} -> result
      end
    end
  end

  describe "commit-before-broadcast crash recovery" do
    test "restart after committed result before broadcast resumes next stage without regeneration" do
      config = Application.get_env(:fullstack, Fullstack.JidoMarketAgents, [])

      Application.put_env(
        :fullstack,
        Fullstack.JidoMarketAgents,
        Enum.reduce(
          [:researcher, :analyzer, :systems, :strategy],
          config,
          fn role, acc ->
            Keyword.put(
              acc,
              :"#{role}_backend",
              {BlockingProbeBackend, owner: self(), model: to_string(role)}
            )
          end
        )
      )

      on_exit(fn -> Application.put_env(:fullstack, Fullstack.JidoMarketAgents, config) end)

      user = user_fixture()
      facts = complete_facts()
      research = research_boundary(facts, "committed-research")

      control = fn pending ->
        %{
          "mode" => "automatic",
          "pending_stage" => pending,
          "boundary_version" => 2,
          "run_ref" => Ecto.UUID.generate(),
          "request_ref" => Ecto.UUID.generate()
        }
      end

      # The four crash windows and their durable evidence (the plan's
      # crash table): windows 1-2 leave no result transition and re-run the
      # same stage; windows 3-4 leave the committed boundary and resume the
      # successor without ever regenerating the committed stage (window 4
      # additionally replays as a fingerprint no-op — no duplicate message
      # or result).
      windows = [
        {1, Map.put(facts, "_pipeline", control.("research")), nil, "researcher"},
        {2, Map.put(facts, "_pipeline", control.("research")), nil, "researcher"},
        {3, Map.put(facts, "_pipeline", control.("analysis")), research, "analyzer"},
        {4, Map.put(facts, "_pipeline", control.("analysis")), research, "analyzer"}
      ]

      for {window, window_facts, window_research, first_role} <- windows do
        {:ok, created} = Conversations.create(user.id)
        {:ok, record} = Conversations.update_state(created, %{validated_data: window_facts})

        if window_research do
          {:ok, _} =
            Conversations.append_message(record.id, %{
              role: "assistant",
              content: "research",
              metadata: %{"type" => "market_research", "result" => window_research}
            })
        end

        {:ok, pid} = Conversation.ensure_started(record.id, user.id)
        assert_receive {:provider, ^first_role, messages}, 2_000

        if window in [3, 4] do
          # No regeneration of the committed research boundary.
          refute_received {:provider, "researcher", _}
          assert List.last(messages)["content"] =~ "committed-research"
        end

        # Each window's world ends before the next: parked provider workers
        # die with their conversation so they cannot pollute the next row.
        DynamicSupervisor.terminate_child(
          Fullstack.JidoMarketAgents.ConversationSupervisor,
          pid
        )
      end
    end
  end

  # ── No-duplicate-on-resume ──────────────────────────────────────────────────
  describe "No duplicate persistence after rehydration" do
    test "restored messages are not re-persisted; only the new turn adds rows" do
      user = user_fixture()
      id = new_persisted_id(user)

      {:ok, pid} = Conversation.ensure_started(id, user.id)
      Conversation.subscribe(id)

      assert {:ok, :accepted, ^id} = Conversation.send_message(id, %{country: "Spain"})
      assert_receive {:extraction_complete, %{conversation_id: ^id, status: :needs_data}}, 2_000

      count_before_kill = length(Conversations.list_messages(id))

      {:ok, _pid2} = kill_and_await_restart(id, pid)
      Conversation.subscribe(id)

      assert {:ok, :accepted, ^id} = Conversation.send_message(id, %{business_market: "fintech"})
      assert_receive {:extraction_complete, %{conversation_id: ^id, status: :needs_data}}, 2_000

      count_after_second_turn = length(Conversations.list_messages(id))

      # Turn 2 adds exactly a user message + an assistant reply (2 rows);
      # nothing from turn 1 is duplicated.
      assert count_after_second_turn == count_before_kill + 2
    end
  end

  describe "lifecycle stage" do
    defp stage_record(user, stage, pending) do
      control = %{
        "mode" => "automatic",
        "pending_stage" => pending,
        "boundary_version" => 1,
        "run_ref" => Ecto.UUID.generate(),
        "request_ref" => Ecto.UUID.generate()
      }

      {:ok, created} = Conversations.create(user.id)

      {:ok, record} =
        Conversations.update_state(created, %{
          validated_data: Map.put(complete_facts(), "_pipeline", control)
        })

      Repo.update_all(from(r in Conversations.Record, where: r.id == ^record.id),
        set: [stage: stage]
      )

      record
    end

    defp probe_backends do
      config = Application.get_env(:fullstack, Fullstack.JidoMarketAgents, [])

      Application.put_env(
        :fullstack,
        Fullstack.JidoMarketAgents,
        Enum.reduce([:researcher, :analyzer, :systems, :strategy], config, fn role, acc ->
          Keyword.put(
            acc,
            :"#{role}_backend",
            {BlockingProbeBackend, owner: self(), model: to_string(role)}
          )
        end)
      )

      on_exit(fn -> Application.put_env(:fullstack, Fullstack.JidoMarketAgents, config) end)
    end

    test "restoration carries the persisted stage" do
      user = user_fixture()

      for stage <- Fullstack.JidoMarketAgents.Conversations.Lifecycle.stages() do
        record = stage_record(user, stage, nil)
        {:ok, pid} = Conversation.ensure_started(record.id, user.id)
        assert :sys.get_state(pid).stage == stage
      end
    end

    test "resuming a stage at or ahead of the persisted stage advances it" do
      probe_backends()
      user = user_fixture()
      record = stage_record(user, :ready, "research")

      {:ok, pid} = Conversation.ensure_started(record.id, user.id)
      assert_receive {:provider, "researcher", _}, 2_000
      assert Conversations.get_for_user(record.id, user.id).stage == :research
      assert :sys.get_state(pid).stage == :research
    end

    test "a pending stage behind the persisted stage is not resumed and the stage stays" do
      user = user_fixture()
      record = stage_record(user, :strategy, "research")

      # init enqueues any resume before this call is served, so a launched
      # stage would already hold a task here.
      {:ok, pid} = Conversation.ensure_started(record.id, user.id)
      assert :sys.get_state(pid).stage == :strategy
      assert :sys.get_state(pid).task == nil
      assert Conversations.get_for_user(record.id, user.id).stage == :strategy
    end
  end
end
