# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :ash_oban, pro?: false

config :galicia_local, Oban,
  engine: Oban.Engines.Basic,
  notifier: Oban.Notifiers.Postgres,
  queues: [
    default: 10,
    business_enrich_pending: 5,
    business_enrich_researched: 5,
    business_enrich_pending_no_website: 5,
    scraper: 2,
    research: 3,
    business_translate_to_spanish: 3
  ],
  repo: GaliciaLocal.Repo,
  plugins: [{Oban.Plugins.Cron, []}]

# Crawly configuration
config :crawly,
  closespider_timeout: 10,
  concurrent_requests_per_domain: 2,
  closespider_itemcount: 500,
  follow_redirects: true,
  middlewares: [
    Crawly.Middlewares.DomainFilter,
    Crawly.Middlewares.UniqueRequest,
    {Crawly.Middlewares.UserAgent, user_agents: [
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    ]},
    {Crawly.Middlewares.RequestOptions, [timeout: 30_000, recv_timeout: 30_000]}
  ],
  pipelines: [
    Crawly.Pipelines.Validate,
    {Crawly.Pipelines.DuplicatesFilter, item_id: :place_id},
    GaliciaLocal.Scraper.Pipelines.SaveToDatabase
  ]

config :ash,
  allow_forbidden_field_for_relationships_by_default?: true,
  include_embedded_source_by_default?: false,
  show_keysets_for_all_actions?: false,
  default_page_type: :keyset,
  policies: [no_filter_static_forbidden_reads?: false],
  keep_read_action_loads_when_loading?: false,
  default_actions_require_atomic?: true,
  read_action_after_action_hooks_in_order?: true,
  bulk_actions_default_to_errors?: true,
  transaction_rollback_on_error?: true,
  known_types: [AshPostgres.Timestamptz, AshPostgres.TimestamptzUsec]

config :spark,
  formatter: [
    remove_parens?: true,
    "Ash.Resource": [
      section_order: [
        :authentication,
        :token,
        :user_identity,
        :postgres,
        :resource,
        :code_interface,
        :actions,
        :policies,
        :pub_sub,
        :preparations,
        :changes,
        :validations,
        :multitenancy,
        :attributes,
        :relationships,
        :calculations,
        :aggregates,
        :identities
      ]
    ],
    "Ash.Domain": [section_order: [:resources, :policies, :authorization, :domain, :execution]]
  ]

config :gettext, default_locale: "en"

config :galicia_local,
  ecto_repos: [GaliciaLocal.Repo],
  generators: [timestamp_type: :utc_datetime],
  base_url: "https://galicialocal.com",
  ash_domains: [GaliciaLocal.Accounts, GaliciaLocal.Directory, GaliciaLocal.Community, GaliciaLocal.Analytics],
  ash_authentication: [return_error_on_invalid_magic_link_token?: true]

# Configure the endpoint
config :galicia_local, GaliciaLocalWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: GaliciaLocalWeb.ErrorHTML, json: GaliciaLocalWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: GaliciaLocal.PubSub,
  live_view: [signing_salt: "zPYZ5An5"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :galicia_local, GaliciaLocal.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  galicia_local: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  galicia_local: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# AppSignal
config :appsignal, :config,
  otp_app: :galicia_local,
  name: "GaliciaLocal",
  push_api_key: System.get_env("APPSIGNAL_PUSH_API_KEY"),
  env: Mix.env(),
  active: config_env() == :prod

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
