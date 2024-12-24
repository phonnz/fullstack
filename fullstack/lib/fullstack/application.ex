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
        {Fullstack.Servers.Generators.Transactions, []}
      ] ++ prod_child()

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
