defmodule FullstackWeb.BusinessDiscoveryEvaluateTest do
  # The Conversation GenServer is started by a DynamicSupervisor and does
  # not own the sandbox connection (sandbox constraint, `data_case.ex:39`,
  # `business-discovery-tasks.md` "Sandbox constraint" section). Any test
  # here that touches Postgres through that process must be `async: false`.
  use FullstackWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Fullstack.JidoMarketAgents
  alias Fullstack.JidoMarketAgents.Conversation
  alias Fullstack.JidoMarketAgents.Conversations

  @evaluate_path "/business-discovery/evaluate"

  setup :register_and_log_in_user

  # Bandit LLM stub harness, reused verbatim from
  # `test/fullstack/jido_market_agents_test.exs` (N2: no test calls a real
  # LLM). Every "send" event in this file goes through the real
  # send_message/4 -> MessageBuffer -> RateLimiter -> Conversation pipeline,
  # so without this stub each submit would hit the network client and log a
  # (harmless but noisy) request failure.
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

    :ok
  end

  # Creates a persisted conversation row AND starts its GenServer under the
  # matching id, per design D3b: "The GenServer id IS the Record's binary_id."
  defp start_conversation!(user) do
    {:ok, record} = Conversations.create(user.id)
    {:ok, _pid} = Conversation.ensure_started(record.id, user.id)
    record
  end

  describe "S13.1 anonymous access is redirected" do
    test "anonymous visitor is redirected to /users/log_in with an error flash", %{conn: conn} do
      conn = Phoenix.ConnTest.build_conn()

      assert {:error, {:redirect, %{to: "/users/log_in", flash: flash}}} =
               live(conn, @evaluate_path)

      assert flash["error"] == "You must log in to access this page."
    end
  end

  describe "S13.2 signed-in access renders" do
    test "the page renders for a signed-in user", %{conn: conn} do
      assert {:ok, _view, html} = live(conn, @evaluate_path)
      assert html =~ "Business Discovery" or html =~ "conversation" or html =~ "New conversation"
    end
  end

  describe "S14.1 / S14.2 sidebar shows only the user's own conversations" do
    test "conversations are listed newest first and never leak across users", %{
      conn: conn,
      user: user
    } do
      other_conn = Phoenix.ConnTest.build_conn()
      other_user = Fullstack.AccountsFixtures.user_fixture()
      other_conn = FullstackWeb.ConnCase.log_in_user(other_conn, other_user)

      {:ok, older} = Conversations.create(user.id)
      # `timestamps()` on this schema is second-precision (naive_datetime);
      # sleep past a full second boundary so `inserted_at` actually differs
      # and the newest-first ordering assertion below is meaningful.
      Process.sleep(1_100)
      {:ok, newer} = Conversations.create(user.id)

      {:ok, _other_record} = Conversations.create(other_user.id)

      {:ok, _view, html} = live(conn, @evaluate_path)

      newer_pos = :binary.match(html, newer.id) |> elem(0)
      older_pos = :binary.match(html, older.id) |> elem(0)
      assert newer_pos < older_pos

      {:ok, _other_view, other_html} = live(other_conn, @evaluate_path)
      refute other_html =~ newer.id
      refute other_html =~ older.id
    end
  end

  describe "S14.3 empty state still allows starting a conversation" do
    test "renders an empty state and a new conversation can be started", %{conn: conn, user: user} do
      {:ok, view, html} = live(conn, @evaluate_path)
      assert html =~ "No conversation" or html =~ "Start a new"
      assert html =~ "message-form"

      assert view
             |> element("button", "New conversation")
             |> render_click()

      path = assert_patch(view)
      assert path == @evaluate_path
      assert Conversations.list_for_user(user.id) == []
      assert Registry.lookup(Fullstack.JidoMarketAgents.ConversationRegistry, "") == []

      html = render(view)
      assert html =~ "message-form"
    end
  end

  describe "S14.4 another user's conversation id returns 404" do
    test "raises Ecto.NoResultsError instead of redirecting", %{conn: conn} do
      other_user = Fullstack.AccountsFixtures.user_fixture()
      {:ok, other_record} = Conversations.create(other_user.id)

      assert_raise Ecto.NoResultsError, fn ->
        live(conn, @evaluate_path <> "/" <> other_record.id)
      end
    end
  end

  describe "the first message creates the conversation" do
    test "submitting from the empty state creates the record, runtime, and patches to its url",
         %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, @evaluate_path)

      html =
        view
        |> form("#message-form", %{"message" => "what about Spain?"})
        |> render_submit()

      path = assert_patch(view)
      conversation_id = List.last(String.split(path, "/"))

      assert path == @evaluate_path <> "/" <> conversation_id
      assert Conversations.get_for_user(conversation_id, user.id)

      assert [_] =
               Registry.lookup(Fullstack.JidoMarketAgents.ConversationRegistry, conversation_id)

      assert html =~ "what about Spain?"
      assert render(view) =~ "what about Spain?"

      assert [conversation] = Conversations.list_for_user(user.id)
      assert conversation.id == conversation_id
      assert render(view) =~ conversation_id
      assert JidoMarketAgents.buffer_status(user.id) == :buffering
    end

    test "the LiveView is subscribed to the new conversation's topic after the first send", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, @evaluate_path)

      view
      |> form("#message-form", %{"message" => "hello"})
      |> render_submit()

      path = assert_patch(view)
      conversation_id = List.last(String.split(path, "/"))
      topic = JidoMarketAgents.topic(conversation_id)

      subscribers =
        Registry.lookup(Fullstack.PubSub, topic)
        |> Enum.filter(fn {pid, _} -> pid == view.pid end)

      assert length(subscribers) == 1
    end

    test "navigating to an existing conversation does not start its runtime", %{
      conn: conn,
      user: user
    } do
      {:ok, record} = Conversations.create(user.id)
      {:ok, _message} = Conversations.append_message(record.id, %{role: "user", content: "hi"})

      {:ok, view, _html} = live(conn, @evaluate_path)
      render_patch(view, @evaluate_path <> "/" <> record.id)

      assert render(view) =~ "hi"

      assert Registry.lookup(Fullstack.JidoMarketAgents.ConversationRegistry, record.id) == []
    end

    test "repeated sends keep exactly one subscription", %{conn: conn, user: user} do
      record = start_conversation!(user)
      {:ok, view, _html} = live(conn, @evaluate_path <> "/" <> record.id)

      view
      |> form("#message-form", %{"message" => "first"})
      |> render_submit()

      view
      |> form("#message-form", %{"message" => "second"})
      |> render_submit()

      topic = JidoMarketAgents.topic(record.id)

      subscribers =
        Registry.lookup(Fullstack.PubSub, topic)
        |> Enum.filter(fn {pid, _} -> pid == view.pid end)

      assert length(subscribers) == 1
    end

    test "blank input in the empty state creates nothing", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, @evaluate_path)

      view
      |> form("#message-form", %{"message" => "   "})
      |> render_submit()

      refute_patched(view)
      assert Conversations.list_for_user(user.id) == []
    end
  end

  describe "conversation start validation" do
    test "subscribes before loading selected conversation history", %{conn: conn, user: user} do
      {:ok, record} = Conversations.create(user.id)
      {:ok, view, _html} = live(conn, @evaluate_path)
      test_pid = self()
      handler_id = {__MODULE__, :history_subscription, make_ref()}
      topic = JidoMarketAgents.topic(record.id)

      :ok =
        :telemetry.attach(
          handler_id,
          [:fullstack, :repo, :query],
          fn _event, _measurements, metadata, _config ->
            if self() == view.pid and
                 String.contains?(metadata.query, ~s(FROM "jido_conversation_messages")) do
              subscribed? =
                Enum.any?(Registry.lookup(Fullstack.PubSub, topic), fn {pid, _} ->
                  pid == self()
                end)

              send(test_pid, {:history_subscription, subscribed?})
            end
          end,
          nil
        )

      on_exit(fn -> :telemetry.detach(handler_id) end)
      render_patch(view, @evaluate_path <> "/" <> record.id)
      assert_receive {:history_subscription, true}
    end

    test "malformed and unknown identifiers return 404", %{conn: conn} do
      for id <- ["not-a-uuid", "abcdefghijklmnop", Ecto.UUID.generate()] do
        assert_raise Ecto.NoResultsError, fn ->
          live(conn, @evaluate_path <> "/" <> id)
        end

        assert Registry.lookup(Fullstack.JidoMarketAgents.ConversationRegistry, id) == []
      end
    end

    test "new conversation startup failure shows a safe error", %{conn: conn} do
      {:ok, view, _html} = live(conn, @evaluate_path)
      supervisor = Fullstack.JidoMarketAgents.ConversationSupervisor

      on_exit(fn ->
        Supervisor.restart_child(Fullstack.Supervisor, supervisor)
      end)

      :ok = Supervisor.terminate_child(Fullstack.Supervisor, supervisor)

      try do
        html =
          view
          |> form("#message-form", %{"message" => "tell me about Spain"})
          |> render_submit()

        assert html =~ "Unable to send your message. Please try again."
        refute html =~ "noproc"
        refute_patched(view)
      after
        assert {:ok, _pid} = Supervisor.restart_child(Fullstack.Supervisor, supervisor)
      end
    end
  end

  describe "S15.1 selecting a conversation renders its history in order" do
    test "messages render in order, user vs assistant distinguished", %{conn: conn, user: user} do
      record = start_conversation!(user)

      {:ok, _} = Conversations.append_message(record.id, %{role: "user", content: "hello there"})
      {:ok, _} = Conversations.append_message(record.id, %{role: "assistant", content: "hi back"})

      {:ok, _view, html} = live(conn, @evaluate_path <> "/" <> record.id)

      user_pos = :binary.match(html, "hello there") |> elem(0)
      assistant_pos = :binary.match(html, "hi back") |> elem(0)
      assert user_pos < assistant_pos
    end
  end

  describe "S15.2 selecting subscribes to the new topic and unsubscribes from the old" do
    test "switching conversations moves the subscription", %{conn: conn, user: user} do
      record_a = start_conversation!(user)
      record_b = start_conversation!(user)

      {:ok, view, _html} = live(conn, @evaluate_path <> "/" <> record_a.id)

      # Subscribed to A: a broadcast on A's topic should reach and update
      # the transcript.
      Phoenix.PubSub.broadcast(
        Fullstack.PubSub,
        JidoMarketAgents.topic(record_a.id),
        {:research_complete,
         %{status: :completed, messages: [%{role: "assistant", content: "from A"}]}}
      )

      assert render(view) =~ "from A"

      # Navigate to B via patch (simulating selecting another conversation).
      {:ok, view, _html} =
        live(conn, @evaluate_path <> "/" <> record_b.id)

      # A broadcast on A's topic must NOT reach this view anymore.
      Phoenix.PubSub.broadcast(
        Fullstack.PubSub,
        JidoMarketAgents.topic(record_a.id),
        {:research_complete,
         %{status: :completed, messages: [%{role: "assistant", content: "stale from A"}]}}
      )

      refute render(view) =~ "stale from A"

      # A broadcast on B's topic must reach it.
      Phoenix.PubSub.broadcast(
        Fullstack.PubSub,
        JidoMarketAgents.topic(record_b.id),
        {:research_complete,
         %{status: :completed, messages: [%{role: "assistant", content: "from B"}]}}
      )

      assert render(view) =~ "from B"
    end
  end

  describe "S16.1 / S16.3 / S16.4 sending a message" do
    test "a submitted message appears immediately", %{conn: conn, user: user} do
      record = start_conversation!(user)

      {:ok, view, _html} = live(conn, @evaluate_path <> "/" <> record.id)

      html =
        view
        |> form("#message-form", %{"message" => "what about Spain?"})
        |> render_submit()

      assert html =~ "what about Spain?"
    end

    test "empty or whitespace-only input sends nothing", %{conn: conn, user: user} do
      record = start_conversation!(user)

      {:ok, view, _html} = live(conn, @evaluate_path <> "/" <> record.id)

      html =
        view
        |> form("#message-form", %{"message" => "   "})
        |> render_submit()

      refute html =~ "phase-buffering"
      assert Conversations.list_messages(record.id) == []
    end

    test "transcript re-renders from payload.messages when a broadcast arrives", %{
      conn: conn,
      user: user
    } do
      record = start_conversation!(user)

      {:ok, view, _html} = live(conn, @evaluate_path <> "/" <> record.id)

      Phoenix.PubSub.broadcast(
        Fullstack.PubSub,
        JidoMarketAgents.topic(record.id),
        {:research_complete,
         %{
           status: :completed,
           messages: [
             %{role: "user", content: "authoritative user msg"},
             %{role: "assistant", content: "authoritative reply"}
           ]
         }}
      )

      html = render(view)
      assert html =~ "authoritative user msg"
      assert html =~ "authoritative reply"
    end

    # The Conversation GenServer builds its in-memory messages with ATOM
    # roles (`%{role: :user}`, `conversation.ex:323`/`352`), and `broadcast/3`
    # puts `state.messages` on the wire verbatim (`conversation.ex:497`).
    # Persisted messages use a `:string` role field
    # (`conversations/message.ex:21`), so the two shapes differ. Every other
    # test in this file hand-builds the payload with string roles, which is a
    # shape production never emits — so the transcript must place an atom
    # `:user` message on the user side, not fall through to the assistant
    # branch.
    test "a broadcast carrying atom roles renders the user message on the user side", %{
      conn: conn,
      user: user
    } do
      record = start_conversation!(user)

      {:ok, view, _html} = live(conn, @evaluate_path <> "/" <> record.id)

      Phoenix.PubSub.broadcast(
        Fullstack.PubSub,
        JidoMarketAgents.topic(record.id),
        {:research_complete,
         %{
           status: :completed,
           messages: [
             %{role: :user, content: "atom user msg"},
             %{role: :assistant, content: "atom assistant msg"}
           ]
         }}
      )

      html = render(view)

      assert html =~ "atom user msg"
      assert html =~ "atom assistant msg"

      # The user bubble carries `justify-end` and the assistant bubble
      # `justify-start` (evaluate.html.heex:45-56). Assert on the markup
      # immediately preceding this message's text, so the check cannot be
      # satisfied by an unrelated bubble elsewhere in the document.
      [before_user_msg | _] = String.split(html, "atom user msg")

      assert String.match?(before_user_msg, ~r/justify-end[^>]*>\s*<div[^>]*>\s*<p[^>]*>\s*$/),
             "atom-role user message rendered on the assistant side: " <>
               inspect(String.slice(before_user_msg, -160, 160))
    end
  end

  describe "S17.1 the indicator appears on submit" do
    test "phase is buffering right after submit", %{conn: conn, user: user} do
      record = start_conversation!(user)
      {:ok, view, _html} = live(conn, @evaluate_path <> "/" <> record.id)

      html =
        view
        |> form("#message-form", %{"message" => "tell me about Spain"})
        |> render_submit()

      assert html =~ "phase-buffering" or html =~ "thinking"
    end
  end

  describe "S17.2 :needs_data clears the indicator" do
    test "extraction_complete with needs_data status clears the phase", %{conn: conn, user: user} do
      record = start_conversation!(user)
      {:ok, view, _html} = live(conn, @evaluate_path <> "/" <> record.id)

      view
      |> form("#message-form", %{"message" => "tell me about Spain"})
      |> render_submit()

      Phoenix.PubSub.broadcast(
        Fullstack.PubSub,
        JidoMarketAgents.topic(record.id),
        {:extraction_complete,
         %{status: :needs_data, messages: [%{role: "assistant", content: "what is your budget?"}]}}
      )

      html = render(view)
      refute html =~ "phase-buffering"
      refute html =~ "phase-researching"
      assert html =~ "what is your budget?"
    end
  end

  describe "S17.3 :research_complete clears the indicator" do
    test "clears the phase", %{conn: conn, user: user} do
      record = start_conversation!(user)
      {:ok, view, _html} = live(conn, @evaluate_path <> "/" <> record.id)

      view
      |> form("#message-form", %{"message" => "tell me about Spain"})
      |> render_submit()

      Phoenix.PubSub.broadcast(
        Fullstack.PubSub,
        JidoMarketAgents.topic(record.id),
        {:research_complete, %{status: :completed, messages: []}}
      )

      html = render(view)
      refute html =~ "phase-buffering"
      refute html =~ "phase-researching"
    end
  end

  describe "S17.4 :error clears the indicator and renders the error" do
    test "clears the phase and shows the error", %{conn: conn, user: user} do
      record = start_conversation!(user)
      {:ok, view, _html} = live(conn, @evaluate_path <> "/" <> record.id)

      view
      |> form("#message-form", %{"message" => "tell me about Spain"})
      |> render_submit()

      Phoenix.PubSub.broadcast(
        Fullstack.PubSub,
        JidoMarketAgents.topic(record.id),
        {:error, %{status: :error, stage: :extraction, reason: "boom", messages: []}}
      )

      html = render(view)
      refute html =~ "phase-buffering"
      refute html =~ "phase-researching"
      assert html =~ "boom" or html =~ "error"
    end
  end

  describe "S17.5 :rate_limited renders the notice with retry_at and no spinner" do
    test "shows retry_at and leaves no spinner running", %{conn: conn, user: user} do
      record = start_conversation!(user)
      {:ok, view, _html} = live(conn, @evaluate_path <> "/" <> record.id)

      view
      |> form("#message-form", %{"message" => "tell me about Spain"})
      |> render_submit()

      retry_at = DateTime.utc_now() |> DateTime.add(900, :second)

      Phoenix.PubSub.broadcast(
        Fullstack.PubSub,
        JidoMarketAgents.topic(record.id),
        {:rate_limited,
         %{conversation_id: record.id, retry_at: retry_at, message: "Rate limit reached."}}
      )

      html = render(view)
      refute html =~ "phase-buffering"
      refute html =~ "phase-researching"
      assert html =~ "Rate limit reached."
    end
  end
end
