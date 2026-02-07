defmodule GaliciaLocal.Directory.Category do
  @moduledoc """
  A category for classifying businesses.
  Organized into priority groups for expat relevance.
  """
  use Ash.Resource,
    otp_app: :galicia_local,
    domain: GaliciaLocal.Directory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "categories"
    repo GaliciaLocal.Repo
  end

  code_interface do
    define :list, action: :read
    define :get_by_id, args: [:id]
    define :get_by_slug, args: [:slug]
    define :create
    define :by_priority, args: [:priority]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:name, :slug, :description, :icon, :priority, :parent_id,
              :search_translation, :search_queries, :enrichment_hints]
    end

    update :update do
      primary? true
      accept [:name, :slug, :description, :icon, :priority, :parent_id,
              :search_translation, :search_queries, :enrichment_hints]
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

    read :by_priority do
      argument :priority, :integer, allow_nil?: false
      filter expr(priority == ^arg(:priority))
      prepare build(sort: [name: :asc])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
      description "English category name"
    end

    attribute :slug, :string do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      public? true
    end

    attribute :icon, :string do
      public? true
      description "Heroicon name for the category"
    end

    attribute :priority, :integer do
      allow_nil? false
      default 4
      public? true
      description "1=Expat Essentials, 2=Daily Life, 3=Lifestyle, 4=Practical"
    end

    attribute :search_translation, :string do
      public? true
      description "Base English search term for Google Places (fallback when no locale translation exists)"
    end

    attribute :search_queries, {:array, :string} do
      public? true
      default []
      description "Google Places search queries. Each is searched separately with city name appended."
    end

    attribute :enrichment_hints, :string do
      public? true
      description "Extra instructions for AI when analyzing businesses in this category"
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :parent, GaliciaLocal.Directory.Category
    has_many :subcategories, GaliciaLocal.Directory.Category do
      destination_attribute :parent_id
    end
    has_many :businesses, GaliciaLocal.Directory.Business
    has_many :translations, GaliciaLocal.Directory.CategoryTranslation
  end

  identities do
    identity :unique_slug, [:slug]
  end

  aggregates do
    count :business_count, :businesses
  end
end
