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

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
