defmodule Fullstack.JidoMarketAgents.ConversationSupervisor do
  @moduledoc "DynamicSupervisor for conversation GenServers"
  use DynamicSupervisor

  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Generous restart budget: each conversation is an independent
    # long-lived GenServer, and one incident that kills several of them
    # (deploy, DB blip, rehydration tests simulating process death) must
    # not terminate the whole conversation fleet. The OTP default (3
    # restarts in 5s) would.
    DynamicSupervisor.init(strategy: :one_for_one, max_restarts: 100, max_seconds: 5)
  end
end
