defmodule Fullstack.JidoMarketAgents.Conversations.Step do
  @moduledoc """
  Caller-owned, non-serializable observer tokens for manual conversation stages.
  A dedicated observer owns the PubSub subscription; opening never submits input.
  """
  alias Fullstack.JidoMarketAgents.{Conversation, Conversations}
  alias __MODULE__.Observer

  defstruct [
    :owner,
    :conversation_id,
    :user_id,
    :pid,
    :observer,
    :monitor_ref,
    :topic,
    :lease_ref,
    :run_ref,
    :request_ref,
    :boundary_version,
    mode: :manual,
    stage_versions: %{}
  ]

  def open(user_id, conversation_id \\ nil, opts \\ [])

  def open(user_id, nil, _opts) do
    run = Ecto.UUID.generate()
    request = Ecto.UUID.generate()

    with {:ok, record} <-
           Conversations.create(user_id, %{
             validated_data: %{
               "_pipeline" => %{
                 "mode" => "manual",
                 "run_ref" => run,
                 "request_ref" => request,
                 "boundary_version" => 0
               }
             }
           }) do
      attach(record, user_id)
    end
  end

  def open(user_id, id, _opts) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         {:ok, user_id} <- Ecto.UUID.cast(user_id),
         %Conversations.Record{} = record <- Conversations.get_for_user(id, user_id) do
      attach(record, user_id)
    else
      _ -> {:error, :not_found}
    end
  end

  @doc "Closes only this lease and observer, leaving accepted stage work alive."
  def close(%__MODULE__{owner: owner} = session) when owner == self() do
    try do
      GenServer.call(session.pid, {:release_step, session.lease_ref})
    catch
      :exit, _ -> :ok
    after
      stop_observer(session.observer)
    end
  end

  def close(%__MODULE__{}), do: {:error, :not_owner}

  defp stop_observer(observer) do
    if Process.alive?(observer), do: GenServer.stop(observer, :normal)
    :ok
  catch
    :exit, _ -> :ok
  end

  defp attach(record, user_id) do
    with {:ok, pid} <- Conversation.ensure_step_started(record.id, user_id),
         {:ok, observer} <- Observer.start(self(), pid, Conversation.topic(record.id)) do
      lease = make_ref()

      case GenServer.call(pid, {:claim_step, user_id, self(), observer, lease}) do
        {:ok, binding} ->
          {:ok,
           struct!(
             __MODULE__,
             Map.merge(binding, %{
               owner: self(),
               conversation_id: record.id,
               user_id: user_id,
               pid: pid,
               observer: observer,
               monitor_ref: GenServer.call(observer, :monitor_ref),
               topic: Conversation.topic(record.id),
               lease_ref: lease
             })
           )}

        error ->
          GenServer.stop(observer)
          error
      end
    end
  end

  defmodule Observer do
    @moduledoc false
    use GenServer

    def start(owner, pid, topic), do: GenServer.start(__MODULE__, {owner, pid, topic})

    @impl true
    def init({owner, pid, topic}) do
      :ok = Phoenix.PubSub.subscribe(Fullstack.PubSub, topic)
      {:ok, %{topic: topic, owner_ref: Process.monitor(owner), runtime_ref: Process.monitor(pid)}}
    end

    @impl true
    def handle_call(:monitor_ref, _from, state), do: {:reply, state.runtime_ref, state}

    @impl true
    def handle_info({:DOWN, _, :process, _, _}, state), do: {:stop, :normal, state}
    def handle_info(_event, state), do: {:noreply, state}

    @impl true
    def terminate(_reason, state) do
      Process.demonitor(state.owner_ref, [:flush])
      Process.demonitor(state.runtime_ref, [:flush])
      Phoenix.PubSub.unsubscribe(Fullstack.PubSub, state.topic)
    end
  end
end
