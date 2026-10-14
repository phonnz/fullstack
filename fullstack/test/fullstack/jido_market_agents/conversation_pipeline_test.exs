defmodule Fullstack.JidoMarketAgents.ConversationPipelineTest do
  use Fullstack.DataCase, async: false
  import Fullstack.AccountsFixtures
  alias Fullstack.JidoMarketAgents.{Conversation, Conversations, MessageBuffer, RateLimiter}

  defmodule Backend do
    @behaviour Fullstack.JidoMarketAgents.LLM.Backend
    def capabilities(_), do: [:json_object]
    def validate_config(_), do: :ok

    def chat_completion(messages, opts) do
      send(opts[:owner], {:provider, self(), opts[:model], messages})

      receive do
        {:reply, result} -> result
        :crash -> exit(:provider_crash)
      end
    end
  end

  setup do
    config = Application.get_env(:fullstack, Fullstack.JidoMarketAgents, [])

    updated =
      Enum.reduce([:validator, :researcher, :analyzer, :systems, :strategy], config, fn role,
                                                                                        acc ->
        Keyword.put(acc, :"#{role}_backend", {Backend, owner: self(), model: to_string(role)})
      end)

    Application.put_env(:fullstack, Fullstack.JidoMarketAgents, updated)
    on_exit(fn -> Application.put_env(:fullstack, Fullstack.JidoMarketAgents, config) end)
    user = user_fixture()
    {:ok, record} = Conversations.create(user.id)
    {:ok, pid} = Conversation.ensure_started(record.id, user.id)
    Conversation.subscribe(record.id)

    on_exit(fn ->
      if Process.alive?(pid),
        do:
          DynamicSupervisor.terminate_child(
            Fullstack.JidoMarketAgents.ConversationSupervisor,
            pid
          )
    end)

    %{id: record.id, pid: pid, user: user}
  end

  def data do
    %{
      country: "Spain",
      business_market: "fintech",
      initial_budget: "50000 EUR",
      final_product_proposal: "Payment app",
      product_price: "10 EUR",
      team_size: %{status: "unknown", count: nil, notes: nil},
      current_tools_systems: %{status: "unknown", items: []},
      repetitive_processes_pain_points: %{status: "unknown", items: []},
      digital_maturity: %{level: "unknown", evidence: nil},
      metrics_baselines: %{status: "unknown", items: []}
    }
  end

  def research,
    do: %{
      market_evidence: [],
      market_gaps: [],
      demand_signals: [],
      sources: [],
      limitations: ["No retrieval"]
    }

  defp reply(worker, result), do: send(worker, {:reply, {:ok, Jason.encode!(result)}})

  test "complete validation enqueues run_stage research", %{id: id, pid: pid} do
    :erlang.trace(pid, true, [:receive])
    Conversation.send_message(id, data())
    assert_receive {:trace, ^pid, :receive, {:run_stage, :research}}, 1_000
    assert_receive {:provider, worker, "researcher", _}, 1_000
    refute worker == pid
    assert {:ok, _, _} = Conversation.resume(id)
    reply(worker, research())
    assert_receive {:research_complete, %{conversation_id: ^id}}, 1_000
  end

  test "blocked provider keeps reads admission and close responsive and preserves queued turns",
       %{id: id, pid: pid, user: user} do
    Conversation.send_message(id, data())
    assert_receive {:provider, worker, "researcher", _}, 1_000
    assert length(Conversations.list_messages(id)) >= 1
    assert {:ok, _, _} = Conversation.resume(id)
    assert {:ok, _} = Conversation.list_messages(id)
    assert :ok = GenServer.call(pid, :close)
    assert {:ok, :accepted, ^id} = Conversation.send_message(id, %{country: "France"})
    reply(worker, research())
    assert_receive {:provider, next, "researcher", _}, 1_000
    assert Conversations.get_for_user(id, user.id).validated_data["country"] == "France"
    reply(next, research())
  end

  test "worker failure is contained and terminal", %{id: id, pid: pid} do
    Conversation.send_message(id, data())
    assert_receive {:provider, worker, "researcher", _}, 1_000
    send(worker, :crash)
    assert_receive {:error, %{stage: :research}}, 1_000
    assert Process.alive?(pid)
  end

  test "owner death terminates linked provider", %{id: id, pid: pid} do
    Conversation.send_message(id, data())
    assert_receive {:provider, worker, "researcher", _}, 1_000
    monitor = Process.monitor(worker)
    DynamicSupervisor.terminate_child(Fullstack.JidoMarketAgents.ConversationSupervisor, pid)
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 1_000
  end

  test "duplicate result DOWN and stale binding cannot commit twice", %{id: id, pid: pid} do
    Conversation.send_message(id, data())
    assert_receive {:provider, worker, "researcher", _}, 1_000
    task = :sys.get_state(pid).task
    send(pid, {make_ref(), {:ok, research()}})
    reply(worker, research())
    assert_receive {:research_complete, _}, 1_000
    send(pid, {task.ref, {:ok, research()}})
    send(pid, {:DOWN, task.ref, :process, worker, :normal})
    assert {:ok, _, _} = Conversation.resume(id)

    assert Enum.count(
             Conversations.list_messages(id),
             &(&1.metadata["type"] == "market_research")
           ) == 1

    refute_receive {:research_complete, _}, 50
  end

  test "stage timeout cancels worker", %{id: id} do
    config = Application.get_env(:fullstack, Fullstack.JidoMarketAgents)

    Application.put_env(
      :fullstack,
      Fullstack.JidoMarketAgents,
      Keyword.put(config, :stage_timeout_ms, 40)
    )

    Conversation.send_message(id, data())
    assert_receive {:provider, worker, "researcher", _}, 1_000
    monitor = Process.monitor(worker)
    assert_receive {:error, %{stage: :research}}, 1_000
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 1_000
  end

  test "concurrent startup returns a single owner" do
    id = Ecto.UUID.generate()

    results =
      1..12
      |> Task.async_stream(fn _ -> Conversation.ensure_started(id) end)
      |> Enum.map(fn {:ok, value} -> value end)

    assert Enum.all?(results, &match?({:ok, _}, &1))
    assert results |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> length() == 1
    {:ok, pid} = hd(results)
    DynamicSupervisor.terminate_child(Fullstack.JidoMarketAgents.ConversationSupervisor, pid)
  end

  test "correlated text envelopes remain paid and retain identity through buffering", %{
    id: id,
    user: user
  } do
    run = Ecto.UUID.generate()
    request = Ecto.UUID.generate()

    assert {:ok, :buffered, ^id} =
             Fullstack.JidoMarketAgents.send_message(user.id, id, "Spain",
               run_ref: run,
               request_ref: request
             )

    assert_receive {:provider, worker, "validator", _}, 1_000
    assert RateLimiter.user_status(user.id) == :active
    entries = :ets.lookup(:rate_limiter, user.id)
    assert length(entries) == 1
    reply(worker, %{country: "Spain"})
    assert_receive {:extraction_complete, %{run_ref: ^run, request_ref: ^request}}, 1_000
    refute MessageBuffer == nil
  end
end
