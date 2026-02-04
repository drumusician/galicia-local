defmodule GaliciaLocal.Directory.CityTranslation do
  @moduledoc """
  Locale-specific translations for city content.
  Supports unlimited languages without schema changes.
  """
  use Ash.Resource,
    otp_app: :galicia_local,
    domain: GaliciaLocal.Directory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "city_translations"
    repo GaliciaLocal.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :locale, :string do
      allow_nil? false
      public? true
      description "Locale code (en, es, nl, etc.)"
    end

    attribute :description, :string do
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :city, GaliciaLocal.Directory.City do
      allow_nil? false
      attribute_writable? true
    end
  end

  identities do
    identity :unique_city_locale, [:city_id, :locale]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:city_id, :locale, :description]
    end

    create :upsert do
      upsert? true
      upsert_identity :unique_city_locale
      accept [:city_id, :locale, :description]
    end

    update :update do
      primary? true
      accept [:description]
    end

    read :for_city_locale do
      argument :city_id, :uuid, allow_nil?: false
      argument :locale, :string, allow_nil?: false
      get? true
      filter expr(city_id == ^arg(:city_id) and locale == ^arg(:locale))
    end

    read :for_city do
      argument :city_id, :uuid, allow_nil?: false
      filter expr(city_id == ^arg(:city_id))
    end
  end

  code_interface do
    define :get_for_city_locale, action: :for_city_locale, args: [:city_id, :locale]
    define :get_for_city, action: :for_city, args: [:city_id]
    define :upsert
    define :list, action: :read
  end
end
