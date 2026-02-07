defmodule GaliciaLocal.Directory.Region do
  @moduledoc """
  A region/country where the platform operates.
  Used as the tenant identifier for multi-tenancy.
  Examples: Netherlands, Galicia (Spain), etc.
  """
  use Ash.Resource,
    otp_app: :galicia_local,
    domain: GaliciaLocal.Directory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "regions"
    repo GaliciaLocal.Repo
  end

  code_interface do
    define :list, action: :read
    define :list_active, action: :active
    define :get_by_id, args: [:id]
    define :get_by_slug, args: [:slug]
    define :create
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:name, :slug, :country_code, :default_locale, :supported_locales, :timezone, :active, :settings, :tagline, :hero_image_url]
    end

    update :update do
      primary? true
      accept [:name, :default_locale, :supported_locales, :timezone, :active, :settings, :tagline, :hero_image_url]
    end

    read :get_by_id do
      argument :id, :uuid, allow_nil?: false
      get? true
      filter expr(id == ^arg(:id))
    end

    read :get_by_slug do
      argument :slug, :string, allow_nil?: false
      get? true
      filter expr(slug == ^arg(:slug))
    end

    read :active do
      filter expr(active == true)
      prepare build(sort: [name: :asc])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
      description "Display name of the region (e.g., 'Netherlands', 'Galicia')"
    end

    attribute :slug, :string do
      allow_nil? false
      public? true
      description "URL-friendly identifier (e.g., 'netherlands', 'galicia')"
    end

    attribute :country_code, :string do
      allow_nil? false
      public? true
      description "ISO 3166-1 alpha-2 country code (e.g., 'NL', 'ES')"
    end

    attribute :default_locale, :string do
      default "en"
      public? true
      description "Default locale for this region"
    end

    attribute :supported_locales, {:array, :string} do
      default ["en"]
      public? true
      description "List of supported locales for this region"
    end

    attribute :timezone, :string do
      default "UTC"
      public? true
      description "Default timezone for this region"
    end

    attribute :active, :boolean do
      default true
      public? true
      description "Whether this region is currently active/visible"
    end

    attribute :tagline, :string do
      public? true
      description "Short tagline for region selector (e.g., 'Celtic heritage, incredible seafood')"
    end

    attribute :hero_image_url, :string do
      public? true
      description "URL for hero background image on the region home page"
    end

    attribute :settings, :map do
      default %{}
      public? true
      description "Region-specific configuration: phrases, cultural_tips, enrichment_context"
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :cities, GaliciaLocal.Directory.City
  end

  identities do
    identity :unique_slug, [:slug]
  end

  aggregates do
    count :city_count, :cities
  end
end
