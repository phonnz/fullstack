defmodule Fullstack.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Telemetry supervisor
      FullstackWeb.Telemetry,
      # Start the Ecto repository
      Fullstack.Repo,
      # Start the PubSub system
      {Phoenix.PubSub, name: Fullstack.PubSub},
      # Start Finch
      {Finch, name: Fullstack.Finch},
      # Start the Endpoint (http/https)
      FullstackWeb.Endpoint
      ## {Fullstack.Servers.Generators.Customers, []},
      ## {Fullstack.Servers.Generators.Transactions, []}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Fullstack.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    FullstackWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
