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
end
