defmodule Fullstack.ChannelsTest do
  use Fullstack.DataCase, async: true

  alias Fullstack.Accounts
  alias Fullstack.Accounts.User
  alias Fullstack.Channels
  alias Fullstack.Channels.Identity
  alias Fullstack.JidoMarketAgents.Conversations

  @from "whatsapp:+5215512345678"

  describe "record_inbound/2" do
    test "returns :new the first time and :duplicate for the same message id" do
      assert Channels.record_inbound("whatsapp", "SM123") == :new
      assert Channels.record_inbound("whatsapp", "SM123") == :duplicate
      assert Channels.record_inbound("whatsapp", "SM456") == :new
    end

    test "scopes message ids per channel" do
      assert Channels.record_inbound("whatsapp", "SM123") == :new
      assert Channels.record_inbound("sms", "SM123") == :new
    end
  end

  describe "resolve_identity/3" do
    test "creates a user with a placeholder email and an identity for an unknown sender" do
      assert {:ok, %Identity{} = identity} = Channels.resolve_identity("whatsapp", @from)

      assert identity.channel == "whatsapp"
      assert identity.external_id == @from
      assert identity.active_conversation_id == nil

      user = Repo.get!(User, identity.user_id)
      assert user.email == "wa-5215512345678@whatsapp.invalid"
      assert user.role == :user
      assert is_binary(user.hashed_password)
    end

    test "returns the same identity and user for a known sender" do
      users_before = Repo.aggregate(User, :count)
      {:ok, first} = Channels.resolve_identity("whatsapp", @from)
      {:ok, second} = Channels.resolve_identity("whatsapp", @from)

      assert first.id == second.id
      assert Repo.aggregate(User, :count) == users_before + 1
    end

    test "the generated password does not authenticate with a guessable value" do
      {:ok, identity} = Channels.resolve_identity("whatsapp", @from)

      refute Accounts.get_user_by_email_and_password(
               "wa-5215512345678@whatsapp.invalid",
               "hello world!"
             )

      assert Repo.get!(User, identity.user_id)
    end

    test "refuses a new sender once the hourly cap is reached and creates nothing" do
      users_before = Repo.aggregate(User, :count)
      {:ok, _} = Channels.resolve_identity("whatsapp", "whatsapp:+111", max_new_per_hour: 2)
      {:ok, _} = Channels.resolve_identity("whatsapp", "whatsapp:+222", max_new_per_hour: 2)

      assert Channels.resolve_identity("whatsapp", "whatsapp:+333", max_new_per_hour: 2) ==
               {:error, :new_user_cap_reached}

      assert Repo.aggregate(User, :count) == users_before + 2
      assert Repo.aggregate(Identity, :count) == 2
    end

    test "a known sender is still resolved when the cap is reached" do
      {:ok, known} = Channels.resolve_identity("whatsapp", "whatsapp:+111", max_new_per_hour: 1)

      assert {:ok, %Identity{id: id}} =
               Channels.resolve_identity("whatsapp", "whatsapp:+111", max_new_per_hour: 1)

      assert id == known.id
    end
  end

  describe "set_active_conversation/2" do
    test "points the identity at a conversation and clears it with nil" do
      {:ok, identity} = Channels.resolve_identity("whatsapp", @from)
      {:ok, record} = Conversations.create(identity.user_id)

      assert {:ok, %Identity{active_conversation_id: id} = identity} =
               Channels.set_active_conversation(identity, record.id)

      assert id == record.id

      assert {:ok, %Identity{active_conversation_id: nil}} =
               Channels.set_active_conversation(identity, nil)
    end

    test "is cleared when the conversation is deleted" do
      {:ok, identity} = Channels.resolve_identity("whatsapp", @from)
      {:ok, record} = Conversations.create(identity.user_id)
      {:ok, identity} = Channels.set_active_conversation(identity, record.id)

      Repo.delete!(record)

      assert Repo.reload!(identity).active_conversation_id == nil
    end
  end

  describe "parse_command/1" do
    test "recognizes /start, /nuevo and /new case-insensitively as the first token" do
      assert Channels.parse_command("/start") == {:new_conversation, ""}
      assert Channels.parse_command("/nuevo") == {:new_conversation, ""}
      assert Channels.parse_command("/NEW") == {:new_conversation, ""}
      assert Channels.parse_command("  /Nuevo  ") == {:new_conversation, ""}
    end

    test "keeps the text after the command as the first message" do
      assert Channels.parse_command("/new I sell coffee in Puebla") ==
               {:new_conversation, "I sell coffee in Puebla"}

      assert Channels.parse_command("/nuevo\nVendo café") == {:new_conversation, "Vendo café"}
    end

    test "treats anything else as a regular message" do
      assert Channels.parse_command("hello") == {:message, "hello"}
      assert Channels.parse_command("/newer idea") == {:message, "/newer idea"}
      assert Channels.parse_command("I said /new earlier") == {:message, "I said /new earlier"}
    end
  end
end
