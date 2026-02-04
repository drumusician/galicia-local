defmodule GaliciaLocal.Directory.BusinessTranslation do
  @moduledoc """
  Locale-specific translations for business content.
  Supports unlimited languages without schema changes.
  """
  use Ash.Resource,
    otp_app: :galicia_local,
    domain: GaliciaLocal.Directory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "business_translations"
    repo GaliciaLocal.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :locale, :string do
      allow_nil? false
      public? true
      description "Locale code (en, es, nl, etc.)"
    end

    # Text fields
    attribute :description, :string do
      public? true
    end

    attribute :summary, :string do
      public? true
    end

    # Array fields
    attribute :highlights, {:array, :string} do
      public? true
      default []
    end

    attribute :warnings, {:array, :string} do
      public? true
      default []
    end

    attribute :integration_tips, {:array, :string} do
      public? true
      default []
    end

    attribute :cultural_notes, {:array, :string} do
      public? true
      default []
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :business, GaliciaLocal.Directory.Business do
      allow_nil? false
      attribute_writable? true
    end
  end

  identities do
    identity :unique_business_locale, [:business_id, :locale]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:business_id, :locale, :description, :summary, :highlights, :warnings, :integration_tips, :cultural_notes]
    end

    create :upsert do
      upsert? true
      upsert_identity :unique_business_locale
      accept [:business_id, :locale, :description, :summary, :highlights, :warnings, :integration_tips, :cultural_notes]
    end

    update :update do
      primary? true
      accept [:description, :summary, :highlights, :warnings, :integration_tips, :cultural_notes]
    end

    read :for_business_locale do
      argument :business_id, :uuid, allow_nil?: false
      argument :locale, :string, allow_nil?: false
      get? true
      filter expr(business_id == ^arg(:business_id) and locale == ^arg(:locale))
    end

    read :for_business do
      argument :business_id, :uuid, allow_nil?: false
      filter expr(business_id == ^arg(:business_id))
    end
  end

  code_interface do
    define :get_for_business_locale, action: :for_business_locale, args: [:business_id, :locale]
    define :get_for_business, action: :for_business, args: [:business_id]
    define :upsert
    define :list, action: :read
  end
end
