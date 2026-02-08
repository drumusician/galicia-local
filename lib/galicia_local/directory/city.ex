defmodule GaliciaLocal.Directory.City do
  @moduledoc """
  A city within a region where businesses are located.
  """
  use Ash.Resource,
    otp_app: :galicia_local,
    domain: GaliciaLocal.Directory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "cities"
    repo GaliciaLocal.Repo
  end

  multitenancy do
    strategy :attribute
    attribute :region_id
    global? true
  end

  code_interface do
    define :list, action: :read
    define :get_by_id, args: [:id]
    define :get_by_slug, args: [:slug]
    define :create
    define :featured
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:name, :slug, :province, :description, :latitude, :longitude, :population, :featured, :image_url, :region_id]
    end

    update :update do
      primary? true
      accept [:name, :slug, :province, :description, :latitude, :longitude, :population, :featured, :image_url, :region_id]
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

    read :featured do
      filter expr(featured == true)
      prepare build(sort: [population: :desc])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :slug, :string do
      allow_nil? false
      public? true
    end

    attribute :province, :string do
      allow_nil? false
      public? true
      description "One of: A Coruña, Lugo, Ourense, Pontevedra"
    end

    attribute :description, :string do
      public? true
      description "English description of the city"
    end

    attribute :latitude, :decimal do
      public? true
      constraints min: -90, max: 90
    end

    attribute :longitude, :decimal do
      public? true
      constraints min: -180, max: 180
    end

    attribute :population, :integer do
      public? true
    end

    attribute :featured, :boolean do
      default false
      public? true
    end

    attribute :image_url, :string do
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

    has_many :businesses, GaliciaLocal.Directory.Business
    has_many :translations, GaliciaLocal.Directory.CityTranslation
  end

  identities do
    identity :unique_slug_per_region, [:slug, :region_id]
  end

  aggregates do
    count :business_count, :businesses do
      filter expr(status in [:enriched, :verified] and not is_nil(description) and not is_nil(summary))
    end
  end
end
