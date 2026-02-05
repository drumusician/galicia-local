defmodule GaliciaLocal.Analytics.PageView do
  use Ash.Resource,
    otp_app: :galicia_local,
    domain: GaliciaLocal.Analytics,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "page_views"
    repo GaliciaLocal.Repo
  end

  actions do
    defaults [:read]

    read :top_resources do
      argument :page_type, :string, allow_nil?: false
      argument :days, :integer, default: 30

      filter expr(page_type == ^arg(:page_type) and date >= ago(^arg(:days), :day))

      prepare build(sort: [view_count: :desc], limit: 20)
    end

    read :by_resource do
      argument :resource_id, :uuid, allow_nil?: false
      argument :days, :integer, default: 30

      filter expr(resource_id == ^arg(:resource_id) and date >= ago(^arg(:days), :day))

      prepare build(sort: [date: :asc])
    end
  end

  identities do
    identity :unique_page_day, [:page_type, :resource_id, :date, :region_id]
  end

  attributes do
    uuid_primary_key :id

    attribute :page_type, :string do
      allow_nil? false
      public? true
    end

    attribute :resource_id, :uuid do
      allow_nil? false
      public? true
    end

    attribute :region_id, :uuid do
      allow_nil? false
      public? true
    end

    attribute :date, :date do
      allow_nil? false
      public? true
    end

    attribute :view_count, :integer do
      default 0
      allow_nil? false
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end
end
