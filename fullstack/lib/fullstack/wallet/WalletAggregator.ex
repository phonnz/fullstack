defmodule Fullstack.Wallet.Aggregate.WalletAggregator do
  use GenServer
  require Logger
  @registry Fullstack.Wallet.Aggregate.WalletAggregators

  defstruct [:customer_id, :value, event_type: :amount_deposited]

  def start_link(customer_id) do
    GenServer.start_link(
      __MODULE__,
      customer_id,
      name: register_via(customer_id)
    )
  end

  def apply_event(%{customer_id: account} = event)
      when is_binary(account) do
    case Registry.lookup(@registry, account) do
      [{pid, _}] ->
        apply_event(pid, event)

      _ ->
        Logger.debug("Attempt to apply event to non-existent account, starting aggregator")
        {:ok, pid} = start_link(account)
        apply_event(pid, event)
    end
  end

  def apply_event(pid, event) when is_pid(pid) do
    GenServer.cast(pid, {:handle_event, event})
  end

  def get_balance(customer_id) when is_binary(customer_id) do
    customer_id
    |> lookup_aggregator
    |> GenServer.call(:get_balance)
  end

  def get_history(customer_id) when is_binary(customer_id) do
    customer_id
    |> lookup_aggregator
    |> GenServer.call(:get_history)
  end

  defp lookup_aggregator(customer_id) when is_binary(customer_id) do
    with [{pid, _}] <-
           Registry.lookup(@registry, customer_id) do
      pid
    else
      _ ->
        {:error, :unknown_account}
    end
  end

  @impl true
  def init(customer_id) do
    {:ok, %{balance: 0, account_number: customer_id, commands: []}}
  end

  @impl true
  def handle_cast({:handle_event, evt}, state) do
    {:noreply, handle_event(state, evt)}
  end

  def handle_event(
        %{balance: _bal} = s,
        %{event_type: :amount_withdrawn, value: v} = evt
      ) do
    s
    |> Map.update(:balance, 0, &(&1 - v))
    |> Map.update(:commands, [], &[evt | &1])
  end

  def handle_event(
        %{balance: _bal} = s,
        %{event_type: :amount_deposited, value: v} = evt
      ) do
    s
    |> Map.update(:balance, 0, &(&1 + v))
    |> Map.update(:commands, [], &[evt | &1])
  end

  def handle_event(
        %{balance: _bal} = s,
        %{event_type: :fee_applied, value: v} = evt
      ) do
    s
    |> Map.update(:balance, 0, &(&1 - v))
    |> Map.update(:commands, [], &[evt | &1])
  end

  @impl true
  def handle_call(:get_balance, _from, state) do
    {:reply, state.balance, state}
  end

  @impl true
  def handle_call(:get_history, _from, state) do
    {:reply, state.commands, state}
  end

  defp register_via(customer_id) do
    {:via, Registry, {@registry, customer_id}}
  end
end
