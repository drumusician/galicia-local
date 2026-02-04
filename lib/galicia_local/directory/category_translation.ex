defmodule GaliciaLocal.Directory.CategoryTranslation do
  @moduledoc """
  Locale-specific translations and search queries for categories.
  Enables region-specific scraping with appropriate language terms.
  """
  use Ash.Resource,
    otp_app: :galicia_local,
    domain: GaliciaLocal.Directory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "category_translations"
    repo GaliciaLocal.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :locale, :string do
      allow_nil? false
      public? true
      description "Locale code (es, nl, pt, de, fr, etc.)"
    end

    attribute :name, :string do
      public? true
      description "Localized category name for display"
    end

    attribute :search_translation, :string do
      public? true
      description "Base search term in this locale"
    end

    attribute :search_queries, {:array, :string} do
      public? true
      default []
      description "Search queries for Google Places in this locale"
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :category, GaliciaLocal.Directory.Category do
      allow_nil? false
      attribute_writable? true
    end
  end

  identities do
    identity :unique_category_locale, [:category_id, :locale]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:category_id, :locale, :name, :search_translation, :search_queries]
    end

    create :upsert do
      upsert? true
      upsert_identity :unique_category_locale
      accept [:category_id, :locale, :name, :search_translation, :search_queries]
    end

    update :update do
      primary? true
      accept [:name, :search_translation, :search_queries]
    end

    read :for_category_locale do
      argument :category_id, :uuid, allow_nil?: false
      argument :locale, :string, allow_nil?: false
      get? true
      filter expr(category_id == ^arg(:category_id) and locale == ^arg(:locale))
    end

    read :by_locale do
      argument :locale, :string, allow_nil?: false
      filter expr(locale == ^arg(:locale))
      prepare build(load: [:category])
    end
  end

  code_interface do
    define :get_for_category_locale, action: :for_category_locale, args: [:category_id, :locale]
    define :upsert
    define :list, action: :read
  end
end
