defmodule GaliciaLocal.Directory.DiscoveryCrawl do
  @moduledoc """
  Tracks discovery crawl progress through the pipeline:
  crawling → crawled → processing → completed/failed.

  The actual crawled page files live on disk (persistent volume in prod).
  This resource tracks metadata and progress for dashboard visibility.
  """
  use Ash.Resource,
    otp_app: :galicia_local,
    domain: GaliciaLocal.Directory,
    data_layer: AshPostgres.DataLayer

  alias GaliciaLocal.Directory.Types.CrawlStatus

  postgres do
    table "discovery_crawls"
    repo GaliciaLocal.Repo
  end

  multitenancy do
    strategy :attribute
    attribute :region_id
    global? true
  end

  code_interface do
    define :list, action: :read
    define :get_by_crawl_id, args: [:crawl_id], action: :by_crawl_id
    define :create
    define :mark_crawled, args: [:pages_crawled]
    define :mark_processing
    define :mark_completed, args: [:businesses_created, :businesses_skipped, :businesses_failed]
    define :mark_failed, args: [:error]
    define :update_pages_crawled, args: [:pages_crawled]
    define :find_incomplete, action: :incomplete
  end

  actions do
    defaults [:destroy]

    read :read do
      primary? true
      prepare build(sort: [inserted_at: :desc])
    end

    create :create do
      primary? true

      accept [
        :crawl_id,
        :seed_urls,
        :max_pages,
        :city_id,
        :region_id
      ]

      change set_attribute(:status, :crawling)
      change set_attribute(:started_at, &DateTime.utc_now/0)
    end

    read :by_crawl_id do
      argument :crawl_id, :string, allow_nil?: false
      get? true
      filter expr(crawl_id == ^arg(:crawl_id))
    end

    read :incomplete do
      filter expr(status in [:crawling, :crawled, :processing])
    end

    update :mark_crawled do
      accept []
      argument :pages_crawled, :integer, allow_nil?: false

      change set_attribute(:status, :crawled)
      change set_attribute(:crawl_finished_at, &DateTime.utc_now/0)
      change set_attribute(:pages_crawled, arg(:pages_crawled))
    end

    update :mark_processing do
      accept []
      change set_attribute(:status, :processing)
      change set_attribute(:processing_started_at, &DateTime.utc_now/0)
    end

    update :mark_completed do
      accept []
      argument :businesses_created, :integer, allow_nil?: false
      argument :businesses_skipped, :integer, allow_nil?: false
      argument :businesses_failed, :integer, allow_nil?: false

      change set_attribute(:status, :completed)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
      change set_attribute(:businesses_created, arg(:businesses_created))
      change set_attribute(:businesses_skipped, arg(:businesses_skipped))
      change set_attribute(:businesses_failed, arg(:businesses_failed))
    end

    update :mark_failed do
      accept []
      argument :error, :string, allow_nil?: false

      change set_attribute(:status, :failed)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
      change set_attribute(:error, arg(:error))
    end

    update :update_pages_crawled do
      accept []
      argument :pages_crawled, :integer, allow_nil?: false
      change set_attribute(:pages_crawled, arg(:pages_crawled))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :crawl_id, :string do
      allow_nil? false
      public? true
    end

    attribute :status, CrawlStatus do
      allow_nil? false
      default :crawling
      public? true
    end

    attribute :seed_urls, {:array, :string} do
      default []
      public? true
    end

    attribute :max_pages, :integer do
      default 200
      public? true
    end

    attribute :pages_crawled, :integer do
      default 0
      public? true
    end

    attribute :businesses_created, :integer do
      default 0
      public? true
    end

    attribute :businesses_skipped, :integer do
      default 0
      public? true
    end

    attribute :businesses_failed, :integer do
      default 0
      public? true
    end

    attribute :error, :string do
      public? true
    end

    attribute :started_at, :utc_datetime do
      public? true
    end

    attribute :crawl_finished_at, :utc_datetime do
      public? true
    end

    attribute :processing_started_at, :utc_datetime do
      public? true
    end

    attribute :completed_at, :utc_datetime do
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :region, GaliciaLocal.Directory.Region do
      allow_nil? true
      attribute_writable? true
    end

    belongs_to :city, GaliciaLocal.Directory.City do
      allow_nil? true
      attribute_writable? true
    end
  end

  identities do
    identity :unique_crawl_id, [:crawl_id]
  end
end
