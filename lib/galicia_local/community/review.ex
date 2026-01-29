defmodule GaliciaLocal.Community.Review do
  use Ash.Resource,
    otp_app: :galicia_local,
    domain: GaliciaLocal.Community,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "reviews"
    repo GaliciaLocal.Repo
  end

  actions do
    defaults [:read]

    create :create do
      accept [:rating, :body, :visited, :speaks_english_confirmed, :business_id]
      change relate_actor(:user)
    end

    read :list_for_business do
      argument :business_id, :uuid, allow_nil?: false
      filter expr(business_id == ^arg(:business_id))
      prepare build(sort: [inserted_at: :desc])
    end

    read :list_for_user do
      argument :user_id, :uuid, allow_nil?: false
      filter expr(user_id == ^arg(:user_id))
      prepare build(sort: [inserted_at: :desc])
    end

    destroy :destroy do
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type(:create) do
      authorize_if actor_present()
    end

    policy action_type(:destroy) do
      authorize_if expr(user_id == ^actor(:id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :rating, :integer do
      allow_nil? false
      public? true
      constraints min: 1, max: 5
    end

    attribute :body, :string do
      public? true
      constraints max_length: 2000
    end

    attribute :visited, :boolean do
      default false
      public? true
    end

    attribute :speaks_english_confirmed, :boolean do
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
end
