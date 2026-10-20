defmodule Fullstack.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        # {Cluster.Supervisor,
        # [Application.get_env(:libcluster, :topologies), [name: Fullstack.ClusterSupervisor]]},
        # Start the Telemetry supervisor
        FullstackWeb.Telemetry,
        Fullstack.Repo,
        {Phoenix.PubSub, name: Fullstack.PubSub},
        {Finch, name: Fullstack.Finch},
        FullstackWeb.Endpoint,
        FullstackWeb.ChatPresence,
        FullstackWeb.Presence,
        {Cachex, [name: :chat]},
        Fullstack.Servers.OperationsSupervisor,
        Fullstack.Services.Counters,
        Fullstack.Servers.Generators.Transactions,
        {Registry, [keys: :unique, name: :wallet_projectors]},
        {Registry, [keys: :unique, name: Fullstack.Wallet.Aggregate.WalletAggregators]},
        {Registry, keys: :unique, name: Fullstack.JidoMarketAgents.ConversationRegistry},
        Fullstack.JidoMarketAgents.RateLimiter,
        Fullstack.JidoMarketAgents.MessageBufferSupervisor,
        Fullstack.JidoMarketAgents.ConversationSupervisor,
        Fullstack.Agents.AgentServer
      ] ++ prod_child()

    # Market-agents trace logging. Opt-in via config so it is a deliberate
    # choice per environment rather than something production inherits:
    # the pipeline crosses five processes and most hand-offs are async, so
    # without this the only signal between "user pressed send" and
    # "research completed" is silence. Attached before the supervisor
    # starts so no conversation can begin un-traced.
    if Application.get_env(:fullstack, Fullstack.JidoMarketAgents, [])
       |> Keyword.get(:trace_logging, false) do
      Fullstack.JidoMarketAgents.Telemetry.Reporter.attach()
    end

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Fullstack.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp prod_child() do
    if Application.get_env(:fullstack, :env) == :prod do
      [
        # {Fullstack.Servers.Generators.Transactions, []},
        {Fullstack.Servers.Generators.Customers, []}
      ]
    else
      []
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    FullstackWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
