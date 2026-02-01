defmodule GaliciaLocal.Community.Suggestion do
  @moduledoc """
  A user-submitted suggestion for a business to add to the directory.
  """
  use Ash.Resource,
    otp_app: :galicia_local,
    domain: GaliciaLocal.Community,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "suggestions"
    repo GaliciaLocal.Repo
  end

  code_interface do
    define :create
    define :list_pending
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:business_name, :city_name, :address, :website, :phone, :reason, :category_id]
      change relate_actor(:user)
    end

    update :update_status do
      accept [:status]
    end

    read :list_pending do
      filter expr(status == :pending)
      prepare build(sort: [inserted_at: :desc])
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if actor_present()
    end

    policy action_type(:create) do
      authorize_if actor_present()
    end

    policy action_type(:update) do
      authorize_if expr(^actor(:is_admin) == true)
    end

    policy action_type(:destroy) do
      authorize_if expr(^actor(:is_admin) == true)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :business_name, :string do
      allow_nil? false
      public? true
    end

    attribute :city_name, :string do
      allow_nil? false
      public? true
      description "Free-text city name (may not match an existing city)"
    end

    attribute :address, :string do
      public? true
    end

    attribute :website, :string do
      public? true
    end

    attribute :phone, :string do
      public? true
    end

    attribute :reason, :string do
      public? true
      description "Why the user recommends this place"
    end

    attribute :status, :atom do
      constraints one_of: [:pending, :approved, :dismissed]
      default :pending
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :user, GaliciaLocal.Accounts.User do
      allow_nil? false
    end

    belongs_to :category, GaliciaLocal.Directory.Category do
      allow_nil? true
      public? true
      attribute_writable? true
    end
  end
end
