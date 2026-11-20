defmodule Fullstack.Channels.WhatsApp.RelayTest do
  # Not async: the relay runs under the application's supervisor and reads
  # persisted messages, so it needs the shared sandbox.
  use Fullstack.DataCase, async: false

  import Fullstack.AccountsFixtures

  alias Fullstack.Channels.Twilio
  alias Fullstack.Channels.WhatsApp.Relay
  alias Fullstack.JidoMarketAgents.{Conversation, Conversations}

  @to "whatsapp:+5215512345678"

  # Stands in for a running Conversation GenServer: registered under the
  # conversation id and answering `:list_messages` like the real one.
  defmodule FakeConversation do
    use GenServer

    def start_link({id, messages}), do: GenServer.start_link(__MODULE__, {id, messages})

    @impl true
    def init({id, messages}) do
      {:ok, _} = Registry.register(Fullstack.JidoMarketAgents.ConversationRegistry, id, nil)
      {:ok, messages}
    end

    @impl true
    def handle_call(:list_messages, _from, messages), do: {:reply, {:ok, messages}, messages}
  end

  setup do
    test_pid = self()

    Req.Test.stub(Twilio, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      params = URI.decode_query(body)
      send(test_pid, {:sent, params["To"], params["Body"]})
      conn |> Plug.Conn.put_status(201) |> Req.Test.json(%{"sid" => "SM1"})
    end)

    %{id: Ecto.UUID.generate()}
  end

  defp start_relay(id, opts \\ []) do
    opts =
      Keyword.merge(
        [
          to: @to,
          login_url_fun: fn conversation_id -> "https://app.test/l/#{conversation_id}" end
        ],
        opts
      )

    {:ok, pid} = Relay.ensure_started(id, opts)
    Req.Test.allow(Twilio, self(), pid)
    pid
  end

  defp broadcast(id, event, payload) do
    Phoenix.PubSub.broadcast(Fullstack.PubSub, Conversation.topic(id), {event, payload})
  end

  defp user(text), do: %{role: :user, content: text, metadata: %{}}

  defp assistant(text, metadata \\ %{}),
    do: %{role: :assistant, content: text, metadata: metadata}

  test "sends each new assistant message once, in order, and skips user messages", %{id: id} do
    start_relay(id)

    first = [user("I sell coffee"), assistant("Which country?")]
    broadcast(id, :extraction_complete, %{messages: first})
    assert_receive {:sent, @to, "Which country?"}

    second = first ++ [user("Mexico"), assistant("What is your budget?"), assistant("And price?")]
    broadcast(id, :extraction_complete, %{messages: second})
    assert_receive {:sent, @to, "What is your budget?"}
    assert_receive {:sent, @to, "And price?"}

    broadcast(id, :message_received, %{messages: second})
    refute_receive {:sent, _, _}, 100
  end

  test "does not resend the history of a resumed conversation", %{id: id} do
    history = [user("hi"), assistant("Old reply")]
    start_supervised!({FakeConversation, {id, history}})
    start_relay(id)

    broadcast(id, :message_received, %{messages: history ++ [user("more"), assistant("New")]})

    assert_receive {:sent, @to, "New"}
    refute_receive {:sent, _, "Old reply"}, 100
  end

  test "takes the persisted history as baseline when the conversation is not running" do
    user = user_fixture()
    {:ok, record} = Conversations.create(user.id)
    {:ok, _} = Conversations.append_message(record.id, %{role: "user", content: "hi"})
    {:ok, _} = Conversations.append_message(record.id, %{role: "assistant", content: "Old"})
    start_relay(record.id)

    rehydrated = [user("hi"), assistant("Old"), user("more"), assistant("New")]
    broadcast(record.id, :message_received, %{messages: rehydrated})

    assert_receive {:sent, @to, "New"}
    refute_receive {:sent, _, "Old"}, 100
  end

  test "splits long text into chunks of at most 1600 characters", %{id: id} do
    start_relay(id)
    long = String.duplicate("word ", 700)

    broadcast(id, :extraction_complete, %{messages: [assistant(long)]})

    assert_receive {:sent, @to, chunk1}
    assert_receive {:sent, @to, chunk2}
    assert_receive {:sent, @to, chunk3}
    refute_receive {:sent, _, _}, 100

    for chunk <- [chunk1, chunk2, chunk3], do: assert(String.length(chunk) <= 1600)
    assert Enum.join([chunk1, chunk2, chunk3], " ") == String.trim(long)
  end

  test "sends a stage result as a notice with a login link, not as JSON", %{id: id} do
    start_relay(id)
    json = Jason.encode!(%{"summary" => "secret analysis"})

    broadcast(id, :research_complete, %{
      messages: [
        assistant(json, %{type: :business_analysis}),
        assistant("{}", %{"type" => "tech_strategy"})
      ]
    })

    assert_receive {:sent, @to, notice}
    assert notice =~ "business analysis is ready"
    assert notice =~ "https://app.test/l/#{id}"
    refute notice =~ "secret analysis"

    assert_receive {:sent, @to, notice}
    assert notice =~ "technology strategy is ready"
  end

  test "still sends a notice when no login link can be built", %{id: id} do
    start_relay(id, login_url_fun: fn _conversation_id -> nil end)

    broadcast(id, :research_complete, %{
      messages: [assistant("{}", %{type: :market_research})]
    })

    assert_receive {:sent, @to, notice}
    assert notice =~ "market research is ready"
    assert notice =~ "Sign in on the web"
    refute notice =~ "Open it here"
  end

  test "tells the sender when the conversation is rate limited", %{id: id} do
    start_relay(id)

    broadcast(id, :rate_limited, %{conversation_id: id})

    assert_receive {:sent, @to, text}
    assert text =~ "faster than I can process"
  end

  test "ensure_started/2 reuses a running relay", %{id: id} do
    pid = start_relay(id)
    assert {:ok, ^pid} = Relay.ensure_started(id, to: @to, login_url_fun: fn _ -> "" end)
  end

  test "stops after the idle timeout", %{id: id} do
    pid = start_relay(id, idle_timeout_ms: 50)
    ref = Process.monitor(pid)

    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500
  end
end
