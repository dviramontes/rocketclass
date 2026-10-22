import Config
config :rocketclass, ecto_repos: [Rocketclass.Repo]

config :rocketclass, Rocketclass.Repo,
  database: Path.expand("../var/#{config_env()}.db", __DIR__),
  pool_size: 5,
  log: false

config :rocketclass, RocketclassWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [formats: [html: RocketclassWeb.ErrorHTML], layout: false],
  http: [ip: {127, 0, 0, 1}, port: 4000],
  secret_key_base: "local-development-only-rocketclass-" <> String.duplicate("0", 64),
  live_view: [signing_salt: "rocketclass-local"],
  pubsub_server: Rocketclass.PubSub

config :phoenix, :json_library, Jason
config :logger, level: :info
