defmodule GaliciaLocal.Directory.ScrapeJob do
  @moduledoc """
  Tracks scraping jobs and their results.
  """
  use Ash.Resource,
    otp_app: :galicia_local,
    domain: GaliciaLocal.Directory,
    data_layer: AshPostgres.DataLayer

  alias GaliciaLocal.Directory.Types.ScrapeSource

  postgres do
    table "scrape_jobs"
    repo GaliciaLocal.Repo
  end

  multitenancy do
    strategy :attribute
    attribute :region_id
    global? true
  end

  code_interface do
    define :list, action: :read
    define :create
    define :mark_completed, args: [:businesses_found, :businesses_created]
    define :mark_failed, args: [:error_message]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:source, :query, :city_id, :category_id, :region_id]
      change set_attribute(:status, :pending)
      change set_attribute(:started_at, &DateTime.utc_now/0)
    end

    update :mark_completed do
      accept []
      argument :businesses_found, :integer, allow_nil?: false
      argument :businesses_created, :integer, allow_nil?: false

      change set_attribute(:status, :completed)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
      change set_attribute(:businesses_found, arg(:businesses_found))
      change set_attribute(:businesses_created, arg(:businesses_created))
    end

    update :mark_failed do
      accept []
      argument :error_message, :string, allow_nil?: false

      change set_attribute(:status, :failed)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
      change set_attribute(:error_message, arg(:error_message))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :source, ScrapeSource do
      allow_nil? false
      public? true
    end

    attribute :query, :string do
      public? true
      description "Search query used for scraping"
    end

    attribute :status, :atom do
      allow_nil? false
      default :pending
      public? true
      constraints one_of: [:pending, :running, :completed, :failed]
    end

    attribute :businesses_found, :integer do
      public? true
      default 0
    end

    attribute :businesses_created, :integer do
      public? true
      default 0
    end

    attribute :error_message, :string do
      public? true
    end

    attribute :started_at, :utc_datetime do
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
      allow_nil? false
      attribute_writable? true
    end

    belongs_to :city, GaliciaLocal.Directory.City
    belongs_to :category, GaliciaLocal.Directory.Category
  end
end
