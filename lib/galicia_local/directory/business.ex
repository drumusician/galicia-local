defmodule GaliciaLocal.Directory.Business do
  @moduledoc """
  A business listing in the Galicia Local directory.
  Contains both raw scraped data and LLM-enriched information.
  """
  use Ash.Resource,
    otp_app: :galicia_local,
    domain: GaliciaLocal.Directory,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshOban]

  alias GaliciaLocal.Directory.Types.{BusinessStatus, ScrapeSource, Language}

  postgres do
    table "businesses"
    repo GaliciaLocal.Repo
  end

  oban do
    triggers do
      # Enrich businesses that have completed research
      trigger :enrich_researched do
        scheduler_cron "*/5 * * * *"
        action :enrich_with_llm
        where expr(status == :researched)
        read_action :read
        max_attempts 3
        worker_module_name __MODULE__.EnrichResearchedWorker
        scheduler_module_name __MODULE__.EnrichResearchedScheduler
      end

      # Fallback: enrich pending businesses that don't have websites
      # (they skip the research phase)
      trigger :enrich_pending_no_website do
        scheduler_cron "*/10 * * * *"
        action :enrich_with_llm
        where expr(status == :pending and is_nil(website))
        read_action :read
        max_attempts 3
        worker_module_name __MODULE__.EnrichPendingWorker
        scheduler_module_name __MODULE__.EnrichPendingScheduler
      end
    end
  end

  code_interface do
    define :list, action: :read
    define :search, args: [:query]
    define :get_by_id, args: [:id]
    define :by_city, args: [:city_id]
    define :by_category, args: [:category_id]
    define :create
    define :enrich_with_llm
    define :english_speaking
    define :recent
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [
        :name, :slug, :description, :description_es, :summary,
        :address, :phone, :email, :website, :google_maps_url,
        :latitude, :longitude, :languages_spoken, :speaks_english, :speaks_english_confidence,
        :rating, :review_count, :price_level,
        :opening_hours, :highlights, :warnings,
        :newcomer_friendly_score, :local_gem_score, :integration_tips, :cultural_notes,
        :expat_friendly_score, :expat_tips, :service_specialties, :sentiment_summary, :review_insights,
        :status, :source, :raw_data, :quality_score, :photo_urls,
        :city_id, :category_id
      ]
    end

    update :update do
      primary? true
      accept [
        :name, :slug, :description, :description_es, :summary,
        :address, :phone, :email, :website, :google_maps_url,
        :latitude, :longitude, :languages_spoken, :speaks_english, :speaks_english_confidence,
        :rating, :review_count, :price_level,
        :opening_hours, :highlights, :warnings,
        :newcomer_friendly_score, :local_gem_score, :integration_tips, :cultural_notes,
        :expat_friendly_score, :expat_tips, :service_specialties, :sentiment_summary, :review_insights,
        :status, :source, :raw_data, :quality_score, :photo_urls,
        :city_id, :category_id, :last_enriched_at
      ]
    end

    update :enrich_with_llm do
      require_atomic? false
      accept []
      change GaliciaLocal.Directory.Business.Changes.EnrichWithLLM
    end

    read :get_by_id do
      argument :id, :uuid, allow_nil?: false
      get? true
      filter expr(id == ^arg(:id))
    end

    read :by_city do
      argument :city_id, :uuid, allow_nil?: false
      filter expr(city_id == ^arg(:city_id) and status in [:enriched, :verified])
      prepare build(sort: [rating: :desc_nils_last, name: :asc])
    end

    read :by_category do
      argument :category_id, :uuid, allow_nil?: false
      filter expr(category_id == ^arg(:category_id) and status in [:enriched, :verified])
      prepare build(sort: [rating: :desc_nils_last, name: :asc])
    end

    read :search do
      argument :query, :string, allow_nil?: false

      filter expr(
        status in [:enriched, :verified] and
        (contains(name, ^arg(:query)) or
         contains(description, ^arg(:query)) or
         contains(address, ^arg(:query)))
      )

      prepare build(sort: [rating: :desc_nils_last])
    end

    read :english_speaking do
      filter expr(speaks_english == true and status in [:enriched, :verified])
      prepare build(sort: [speaks_english_confidence: :desc_nils_last, rating: :desc_nils_last])
    end

    read :recent do
      filter expr(status in [:enriched, :verified])
      prepare build(sort: [inserted_at: :desc], limit: 6)
    end
  end

  attributes do
    uuid_primary_key :id

    # Basic info
    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :slug, :string do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      public? true
      description "English description (LLM-generated from reviews)"
    end

    attribute :description_es, :string do
      public? true
      description "Original Spanish description"
    end

    attribute :summary, :string do
      public? true
      description "Short LLM-generated summary"
    end

    # Contact info
    attribute :address, :string do
      public? true
    end

    attribute :phone, :string do
      public? true
    end

    attribute :email, :string do
      public? true
    end

    attribute :website, :string do
      public? true
    end

    attribute :google_maps_url, :string do
      public? true
    end

    # Location
    attribute :latitude, :decimal do
      public? true
      constraints min: -90, max: 90
    end

    attribute :longitude, :decimal do
      public? true
      constraints min: -180, max: 180
    end

    # Language info (LLM-detected)
    attribute :languages_spoken, {:array, Language} do
      public? true
      default []
      description "Languages detected from reviews/website"
    end

    attribute :speaks_english, :boolean do
      public? true
      description "LLM-detected English capability"
    end

    attribute :speaks_english_confidence, :decimal do
      public? true
      constraints min: 0, max: 1
      description "Confidence score for English detection"
    end

    # Ratings and reviews
    attribute :rating, :decimal do
      public? true
      constraints min: 0, max: 5
    end

    attribute :review_count, :integer do
      public? true
      default 0
    end

    attribute :price_level, :integer do
      public? true
      constraints min: 1, max: 4
      description "1-4 euro signs"
    end

    # LLM-extracted info
    attribute :opening_hours, :map do
      public? true
      description "Structured opening hours by day"
    end

    attribute :highlights, {:array, :string} do
      public? true
      default []
      description "LLM-extracted highlights from reviews"
    end

    attribute :warnings, {:array, :string} do
      public? true
      default []
      description "LLM-extracted warnings (cash only, etc.)"
    end

    # Newcomer & Integration insights (LLM-extracted)
    attribute :newcomer_friendly_score, :decimal do
      public? true
      constraints min: 0, max: 1
      description "How accessible for newcomers trying to integrate (0-1)"
    end

    attribute :local_gem_score, :decimal do
      public? true
      constraints min: 0, max: 1
      description "How authentically Galician/local this place is (0-1)"
    end

    attribute :integration_tips, {:array, :string} do
      public? true
      default []
      description "Tips for newcomers to integrate and connect with locals"
    end

    attribute :cultural_notes, {:array, :string} do
      public? true
      default []
      description "Galician cultural context and local customs to know"
    end

    attribute :service_specialties, {:array, :string} do
      public? true
      default []
      description "Specific services mentioned in reviews"
    end

    attribute :sentiment_summary, :string do
      public? true
      description "Overall sentiment analysis from reviews"
    end

    attribute :review_insights, :map do
      public? true
      description "Structured insights extracted from reviews"
    end

    # Legacy field - keeping for backwards compatibility
    attribute :expat_friendly_score, :decimal do
      public? true
      constraints min: 0, max: 1
      description "Deprecated: use newcomer_friendly_score instead"
    end

    attribute :expat_tips, {:array, :string} do
      public? true
      default []
      description "Deprecated: use integration_tips instead"
    end

    # Status and meta
    attribute :status, BusinessStatus do
      default :pending
      public? true
    end

    attribute :source, ScrapeSource do
      public? true
    end

    attribute :raw_data, :map do
      description "Raw scraped data for reference"
    end

    attribute :photo_urls, {:array, :string} do
      public? true
      default []
      description "Google Places photo URLs"
    end

    attribute :quality_score, :decimal do
      public? true
      constraints min: 0, max: 1
      description "Overall data quality score"
    end

    attribute :last_enriched_at, :utc_datetime do
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :city, GaliciaLocal.Directory.City do
      allow_nil? false
    end

    belongs_to :category, GaliciaLocal.Directory.Category do
      allow_nil? false
    end
  end

  identities do
    identity :unique_slug_per_city, [:slug, :city_id]
  end

  calculations do
    calculate :display_rating, :string, expr(
      if is_nil(rating) do
        "No rating"
      else
        fragment("ROUND(?, 1)::text", rating)
      end
    )

    calculate :has_location?, :boolean, expr(not is_nil(latitude) and not is_nil(longitude))
  end
end
