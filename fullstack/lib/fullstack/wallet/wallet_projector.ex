defmodule Fullstack.Wallet.WalletProjector do
  use GenServer
  require Logger

  @registry :wallet_projectors
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
        Logger.debug("Attempt to apply event to non-existent account, starting projector")
        {:ok, pid} = start_link(account)
        apply_event(pid, event)
    end
  end

  def apply_event(pid, event) when is_pid(pid) do
    GenServer.cast(pid, {:handle_event, event})
  end

  def get_balance(pid) do
    GenServer.call(pid, :get_balance)
  end

  def lookup_balance(customer_id) when is_binary(customer_id) do
    with [{pid, _}] <-
           Registry.lookup(@registry, customer_id) do
      {:ok, get_balance(pid)}
    else
      _ ->
        {:error, :unknown_account}
    end
  end

  @impl true
  def init(customer_id) do
    {:ok, %{balance: 0, account_number: customer_id}}
  end

  @impl true
  def handle_cast({:handle_event, evt}, state) do
    {:noreply, handle_event(state, evt)}
  end

  def handle_event(
        %{balance: bal} = s,
        %{event_type: :amount_withdrawn, value: v}
      ) do
    %{s | balance: bal - v}
  end

  def handle_event(
        %{balance: bal} = s,
        %{event_type: :amount_deposited, value: v}
      ) do
    %{s | balance: bal + v}
  end

  def handle_event(
        %{balance: bal} = s,
        %{event_type: :fee_applied, value: v}
      ) do
    %{s | balance: bal - v}
  end

  @impl true
  def handle_call(:get_balance, _from, state) do
    {:reply, state.balance, state}
  end

  defp register_via(customer_id) do
    {:via, Registry, {@registry, customer_id}}
  end
end
