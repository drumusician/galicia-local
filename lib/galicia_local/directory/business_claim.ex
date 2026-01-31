defmodule GaliciaLocal.Directory.BusinessClaim do
  use Ash.Resource,
    otp_app: :galicia_local,
    domain: GaliciaLocal.Directory,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "business_claims"
    repo GaliciaLocal.Repo
  end

  actions do
    defaults [:read]

    create :create do
      accept [:business_id, :message]
      change relate_actor(:user)
      change set_attribute(:status, :pending)
    end

    update :approve do
      accept [:admin_notes]
      change set_attribute(:status, :approved)
      change set_attribute(:reviewed_at, &DateTime.utc_now/0)
    end

    update :reject do
      accept [:admin_notes]
      change set_attribute(:status, :rejected)
      change set_attribute(:reviewed_at, &DateTime.utc_now/0)
    end

    read :list_pending do
      filter expr(status == :pending)
      prepare build(sort: [inserted_at: :asc])
    end

    read :for_user do
      argument :user_id, :uuid, allow_nil?: false
      filter expr(user_id == ^arg(:user_id))
      prepare build(sort: [inserted_at: :desc])
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    policy action(:create) do
      authorize_if actor_present()
    end

    policy action([:approve, :reject]) do
      authorize_if expr(^actor(:is_admin) == true)
    end

    policy action_type(:read) do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :status, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:pending, :approved, :rejected]
      default :pending
    end

    attribute :message, :string do
      public? true
      constraints max_length: 1000
      description "Owner's message explaining their claim"
    end

    attribute :admin_notes, :string do
      public? true
      constraints max_length: 1000
    end

    attribute :reviewed_at, :utc_datetime do
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :user, GaliciaLocal.Accounts.User do
      allow_nil? false
    end

    belongs_to :business, GaliciaLocal.Directory.Business do
      allow_nil? false
      public? true
      attribute_writable? true
    end
  end

  identities do
    identity :unique_user_business, [:user_id, :business_id]
  end
end
