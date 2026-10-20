import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :fullstack, Fullstack.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "fullstack_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10,
  port: 5433

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :fullstack, FullstackWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  secret_key_base: "Ht7b80Z4M/i3pYxj1jkNme51b64wzsaVXt7ZByYS4F9VoVKDLwCOZfdrXwpITCNV",
  server: false

config :libcluster,
  topologies: [
    fullstack: [
      strategy: Cluster.Strategy.Gossip
    ]
  ]

# In test we don't send emails.
config :fullstack, Fullstack.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters.
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Short, deterministic throttling durations so tests never wait on production
# timers (spec N3). See Fullstack.JidoMarketAgents.RateLimiter. cooldown_ms is
# kept comfortably longer than rate_limit_window_ms so that once cooldown
# ends, the entries that triggered it have already aged out of the window —
# otherwise a batch sent right after cooldown would be correctly re-denied by
# the still-sliding window, which is real behavior but not what S9.4 tests.
config :fullstack, Fullstack.JidoMarketAgents,
  debounce_ms: 50,
  rate_limit_count: 3,
  rate_limit_window_ms: 200,
  cooldown_ms: 400
