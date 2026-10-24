# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config
config :fullstack, env: Mix.env()

config :fullstack,
  ecto_repos: [Fullstack.Repo],
  generators: [binary_id: true],
  transactions: [start: true, time_to_generate: 5 * 60_000]

# Per-host root path rewrite, see FullstackWeb.Plugs.HostRewrite.
config :fullstack, :host_roots, %{
  "chat.agentson.live" => "/chat",
  "agentson.live" => "/about",
  "discover.agentson.live" => "/business-discovery"
}

# Throttling durations for Fullstack.JidoMarketAgents.RateLimiter and MessageBuffer.
# Read at runtime via Application.get_env/3, never as module attributes, so test
# config takes effect (see config/test.exs for short deterministic values).
config :fullstack, Fullstack.JidoMarketAgents,
  debounce_ms: 45_000,
  rate_limit_count: 10,
  rate_limit_window_ms: 30 * 60 * 1000,
  cooldown_ms: 15 * 60 * 1000,
  # Approved deployment budgets; JSON completeness still requires runtime measurement.
  default_output_language: "en",
  stage_timeout_ms: 120_000,
  systems_knowledge_max_chars: 24_000,
  strategy_knowledge_max_chars: 24_000,
  validator_backend:
    {Fullstack.JidoMarketAgents.LLM.Mimo,
     model: "mimo-v2.6-pro", temperature: 0.3, max_tokens: 1024, thinking: :disabled},
  researcher_backend:
    {Fullstack.JidoMarketAgents.LLM.Mimo, model: "mimo-v2.6-pro", max_tokens: 4096},
  analyzer_backend:
    {Fullstack.JidoMarketAgents.LLM.Mimo, model: "mimo-v2.6-pro", max_tokens: 6144},
  systems_backend:
    {Fullstack.JidoMarketAgents.LLM.Mimo, model: "mimo-v2.6-pro", max_tokens: 8192},
  strategy_backend:
    {Fullstack.JidoMarketAgents.LLM.Mimo, model: "mimo-v2.6-pro", max_tokens: 8192}

# Configures the endpoint
config :fullstack, FullstackWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [
    formats: [html: FullstackWeb.ErrorHTML, json: FullstackWeb.ErrorJSON],
    layout: false
  ],
  live_reload: [
    patterns: [],
    web_console_logger: true
  ],
  pubsub_server: Fullstack.PubSub,
  live_view: [signing_salt: "c8Pq9B5y"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :fullstack, Fullstack.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  default: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/* --external:vega-embed --external:maplibre-gl),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.3.2",
  default: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :money,
  default_currency: :EUR

# Emails that are granted the :admin role automatically — both when the
# add_user_role migration backfills existing rows and when one of these
# addresses registers later. Empty by default; set per environment.
config :fullstack, bootstrap_admin_emails: []

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
