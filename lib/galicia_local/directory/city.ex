defmodule GaliciaLocal.Directory.City do
  @moduledoc """
  A city in Galicia where businesses are located.
  """
  use Ash.Resource,
    otp_app: :galicia_local,
    domain: GaliciaLocal.Directory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "cities"
    repo GaliciaLocal.Repo
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
      accept [:name, :slug, :province, :description, :description_es, :latitude, :longitude, :population, :featured, :image_url]
    end

    update :update do
      primary? true
      accept [:name, :slug, :province, :description, :description_es, :latitude, :longitude, :population, :featured, :image_url]
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

    attribute :description_es, :string do
      public? true
      description "Spanish description of the city"
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
    has_many :businesses, GaliciaLocal.Directory.Business
  end

  identities do
    identity :unique_slug, [:slug]
  end

  aggregates do
    count :business_count, :businesses do
      filter expr(status in [:enriched, :verified])
    end
  end
end
