defmodule FullstackWeb.TwilioWebhookControllerTest do
  # Not async: the relay and the conversation run under the application's
  # supervisors and need the shared sandbox and a shared Req.Test stub.
  use FullstackWeb.ConnCase, async: false

  alias Fullstack.Accounts.User
  alias Fullstack.Repo
  alias Fullstack.Channels.{Identity, InboundMessage, Twilio}
  alias Fullstack.JidoMarketAgents.{ConversationSupervisor, MessageBufferSupervisor}
  alias Fullstack.JidoMarketAgents.Conversations.Record

  @path "/webhooks/twilio/whatsapp"
  @from "whatsapp:+5215512345678"
  @registry Fullstack.JidoMarketAgents.ConversationRegistry

  # Every LLM role fails, so the pipeline answers with its error message
  # without any network call.
  defmodule FailingBackend do
    @behaviour Fullstack.JidoMarketAgents.LLM.Backend
    def capabilities(_), do: [:json_object]
    def validate_config(_), do: :ok
    def chat_completion(_messages, _opts), do: {:error, :unavailable}
  end

  setup do
    test_pid = self()
    Req.Test.set_req_test_to_shared()

    Req.Test.stub(Twilio, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      params = URI.decode_query(body)
      send(test_pid, {:sent, params["To"], params["Body"]})
      conn |> Plug.Conn.put_status(201) |> Req.Test.json(%{"sid" => "SMout"})
    end)

    agents = Application.get_env(:fullstack, Fullstack.JidoMarketAgents, [])

    failing =
      Enum.reduce([:validator, :researcher, :analyzer, :systems, :strategy], agents, fn role,
                                                                                        acc ->
        Keyword.put(acc, :"#{role}_backend", {FailingBackend, model: "fail"})
      end)

    Application.put_env(:fullstack, Fullstack.JidoMarketAgents, failing)

    before = running_children()

    on_exit(fn ->
      Application.put_env(:fullstack, Fullstack.JidoMarketAgents, agents)
      Application.delete_env(:fullstack, Fullstack.Channels)
      stop_children_started_since(before)
    end)

    :ok
  end

  defp running_children do
    for sup <- [ConversationSupervisor, MessageBufferSupervisor],
        {_, pid, _, _} <- DynamicSupervisor.which_children(sup),
        into: MapSet.new(),
        do: {sup, pid}
  end

  defp stop_children_started_since(before) do
    running_children()
    |> MapSet.difference(before)
    |> Enum.each(fn {sup, pid} -> DynamicSupervisor.terminate_child(sup, pid) end)
  end

  defp params(body, sid) do
    %{"From" => @from, "To" => "whatsapp:+14155238886", "Body" => body, "MessageSid" => sid}
  end

  defp signed_post(conn, params) do
    signature = Twilio.signature(FullstackWeb.Endpoint.url() <> @path, params, "test_auth_token")

    conn
    |> put_req_header("x-twilio-signature", signature)
    |> post(@path, params)
  end

  defp identity, do: Repo.get_by!(Identity, external_id: @from)

  describe "signature" do
    test "rejects a request with an invalid signature and changes nothing", %{conn: conn} do
      users = Repo.aggregate(User, :count)

      conn =
        conn
        |> put_req_header("x-twilio-signature", "forged")
        |> post(@path, params("hello", "SM1"))

      assert response(conn, 403) == ""
      assert Repo.aggregate(User, :count) == users
      assert Repo.aggregate(Identity, :count) == 0
      assert Repo.aggregate(InboundMessage, :count) == 0
    end

    test "rejects a request without a signature", %{conn: conn} do
      assert conn |> post(@path, params("hello", "SM1")) |> response(403) == ""
      assert Repo.aggregate(InboundMessage, :count) == 0
    end

    test "rejects a request signed for different parameters", %{conn: conn} do
      signature =
        Twilio.signature(
          FullstackWeb.Endpoint.url() <> @path,
          params("hello", "SM1"),
          "test_auth_token"
        )

      conn =
        conn
        |> put_req_header("x-twilio-signature", signature)
        |> post(@path, params("tampered", "SM1"))

      assert response(conn, 403) == ""
    end
  end

  describe "inbound messages" do
    test "a first message creates the sender, starts a conversation and gets the agent reply",
         %{conn: conn} do
      conn = signed_post(conn, params("I sell coffee in Puebla", "SM1"))

      assert response(conn, 200) ==
               ~s(<?xml version="1.0" encoding="UTF-8"?><Response></Response>)

      assert response_content_type(conn, :xml)

      identity = identity()
      assert Repo.get!(User, identity.user_id).email == "wa-5215512345678@whatsapp.invalid"
      assert %Record{user_id: user_id} = Repo.get!(Record, identity.active_conversation_id)
      assert user_id == identity.user_id

      assert [{_, _}] =
               Registry.lookup(@registry, {:whatsapp_relay, identity.active_conversation_id})

      # The agent's answer (here the pipeline's error message) reaches WhatsApp.
      assert_receive {:sent, @from, "Stage failed. Please try again."}, 2_000
    end

    test "a later message continues the active conversation", %{conn: conn} do
      signed_post(conn, params("first", "SM1"))
      first = identity().active_conversation_id

      signed_post(build_conn(), params("second", "SM2"))

      assert identity().active_conversation_id == first
      assert Repo.aggregate(Record, :count) == 1
    end

    test "a repeated MessageSid is acknowledged and not processed again", %{conn: conn} do
      signed_post(conn, params("first", "SM1"))
      active = identity().active_conversation_id

      conn = signed_post(build_conn(), params("/new", "SM1"))

      assert response(conn, 200) =~ "<Response></Response>"
      assert identity().active_conversation_id == active
      assert Repo.aggregate(InboundMessage, :count) == 1
    end

    test "a bare /start, /nuevo or /new clears the active conversation and acknowledges it",
         %{conn: conn} do
      signed_post(conn, params("first", "SM1"))

      for {command, sid} <- [{"/start", "SM2"}, {"/nuevo", "SM3"}, {"/NEW", "SM4"}] do
        conn = signed_post(build_conn(), params(command, sid))

        assert response(conn, 200) =~ "<Message>Started a new conversation."
        assert identity().active_conversation_id == nil
      end

      assert Repo.aggregate(Record, :count) == 1
    end

    test "a command with text starts a new conversation with that text", %{conn: conn} do
      signed_post(conn, params("first", "SM1"))
      first = identity().active_conversation_id

      conn = signed_post(build_conn(), params("/nuevo Vendo café en Puebla", "SM2"))

      assert response(conn, 200) =~ "<Response></Response>"
      second = identity().active_conversation_id
      assert second && second != first
      assert Repo.aggregate(Record, :count) == 2
    end

    test "a message without text gets a text-only notice", %{conn: conn} do
      conn = signed_post(conn, params("", "SM1"))

      assert response(conn, 200) =~ "<Message>For now I can only read text messages."
      assert identity().active_conversation_id == nil
    end

    test "a new sender over the hourly cap is told to retry and nothing is created",
         %{conn: conn} do
      Application.put_env(:fullstack, Fullstack.Channels, max_new_per_hour: 0)
      users = Repo.aggregate(User, :count)

      conn = signed_post(conn, params("hello", "SM1"))

      assert response(conn, 200) =~ "<Message>We are receiving many new conversations"
      assert Repo.aggregate(User, :count) == users
      assert Repo.aggregate(Identity, :count) == 0
    end

    test "a signed request without From or MessageSid is rejected", %{conn: conn} do
      conn = signed_post(conn, Map.delete(params("hello", "SM1"), "MessageSid"))

      assert response(conn, 400) == ""
      assert Repo.aggregate(InboundMessage, :count) == 0
    end
  end
end
