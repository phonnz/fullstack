defmodule Fullstack.Services.Counters do
  use GenServer
  @table_name :counters

  def get(_user_id, counter_id) when counter_id == :centralized do
    {:centralized, get(counter_id)}
  end

  def get(user_id, counter_id) when counter_id == :identified do
    {:identified, get(user_id)}
  end

  defp get(counter_name) do
    case :ets.lookup(@table_name, counter_name) do
      [] ->
        :ets.insert_new(@table_name, {counter_name, 0})
        0

      [{counter_name, value} | _] when is_integer(value) ->
        value
    end
  end

  def increase(user_id, counter_id) do
    counter_name = if counter_id == :centralized, do: :centralized, else: user_id
    updated_counter = GenServer.call(__MODULE__, {:inc, counter_name})
    FullstackWeb.Endpoint.broadcast("centralized_counter", "updated_counter", updated_counter)
    updated_counter
  end

  def decrease(user_id, counter_id) do
    counter_name = if counter_id == :centralized, do: :centralized, else: user_id
    updated_counter = GenServer.call(__MODULE__, {:dec, counter_name})
    FullstackWeb.Endpoint.broadcast("centralized_counter", "updated_counter", updated_counter)
    updated_counter
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, %{table_name: Keyword.get(args, :table_name, @table_name)},
      name: __MODULE__
    )
  end

  @impl true
  def init(state) do
    :ets.new(state.table_name, [:set, :public, :named_table, read_concurrency: true])
    {:ok, state}
  end

  @impl true
  def handle_call({:dec, counter_id}, _from, state) do
    result = :ets.update_counter(state.table_name, counter_id, {2, -1})
    {:reply, {counter_id, result}, state}
  end

  def handle_call({:inc, counter_id}, _from, state) do
    result = :ets.update_counter(state.table_name, counter_id, {2, 1})
    {:reply, {counter_id, result}, state}
  end
end
