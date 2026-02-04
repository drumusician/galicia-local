defmodule GaliciaLocal.Repo.Migrations.SeedCategoryTranslations do
  @moduledoc """
  Seeds category translations for Spanish (from existing data) and Dutch (new).
  """
  use Ecto.Migration

  @dutch_translations %{
    "lawyers" => %{name: "Advocaten", search_translation: "advocaten", search_queries: ["advocaten", "advocatenkantoor", "juridisch advies", "notaris", "rechtsbijstand"]},
    "accountants" => %{name: "Accountants", search_translation: "accountants", search_queries: ["accountant", "boekhouder", "belastingadviseur", "administratiekantoor"]},
    "doctors" => %{name: "Artsen", search_translation: "huisarts", search_queries: ["huisarts", "dokter", "medisch centrum", "kliniek", "gezondheidscentrum"]},
    "dentists" => %{name: "Tandartsen", search_translation: "tandarts", search_queries: ["tandarts", "tandartspraktijk", "mondhygienist", "orthodontist"]},
    "restaurants" => %{name: "Restaurants", search_translation: "restaurant", search_queries: ["restaurant", "eetcafe", "bistro", "brasserie", "afhaalrestaurant"]},
    "real-estate" => %{name: "Makelaars", search_translation: "makelaar", search_queries: ["makelaar", "vastgoed", "huurwoning", "koopwoning", "woningverhuur"]},
    "banks" => %{name: "Banken", search_translation: "bank", search_queries: ["bank", "bankfiliaal", "hypotheek adviseur", "financieel adviseur"]},
    "supermarkets" => %{name: "Supermarkten", search_translation: "supermarkt", search_queries: ["supermarkt", "albert heijn", "jumbo", "lidl", "aldi", "plus"]},
    "pharmacies" => %{name: "Apotheken", search_translation: "apotheek", search_queries: ["apotheek", "drogist", "etos", "kruidvat"]},
    "gyms" => %{name: "Sportscholen", search_translation: "sportschool", search_queries: ["sportschool", "fitnesscentrum", "gym", "basic fit", "fit for free"]},
    "hairdressers" => %{name: "Kappers", search_translation: "kapper", search_queries: ["kapper", "kapsalon", "barbier", "haarstudio"]},
    "vets" => %{name: "Dierenartsen", search_translation: "dierenarts", search_queries: ["dierenarts", "dierenkliniek", "dierenziekenhuis"]},
    "language-schools" => %{name: "Taalscholen", search_translation: "taalschool", search_queries: ["taalschool", "nederlands leren", "inburgeringscursus", "NT2", "taallessen"]},
    "mechanics" => %{name: "Garages", search_translation: "garage", search_queries: ["garage", "automonteur", "APK keuring", "autoservice", "autogarage"]},
    "cider-houses" => %{name: "Cafes", search_translation: "cafe", search_queries: ["cafe", "kroeg", "bruin cafe", "grand cafe", "eetcafe"]},
    "bakeries" => %{name: "Bakkerijen", search_translation: "bakker", search_queries: ["bakker", "bakkerij", "brood", "banketbakker"]},
    "coffee-shops" => %{name: "Koffiezaken", search_translation: "koffiebar", search_queries: ["koffiebar", "koffiezaak", "espressobar", "koffiehuis"]}
  }

  def up do
    # Phase 1: Migrate existing Spanish data from categories table
    execute """
    INSERT INTO category_translations (id, category_id, locale, name, search_translation, search_queries, inserted_at, updated_at)
    SELECT
      gen_random_uuid(),
      id,
      'es',
      name_es,
      search_translation,
      COALESCE(search_queries, '{}'),
      NOW(),
      NOW()
    FROM categories
    WHERE name_es IS NOT NULL OR search_translation IS NOT NULL OR array_length(search_queries, 1) > 0
    """

    # Phase 2: Insert Dutch translations
    for {slug, translation} <- @dutch_translations do
      name = translation.name
      search_translation = translation.search_translation
      # PostgreSQL uses single quotes for strings in ARRAY
      search_queries = Enum.map(translation.search_queries, &"'#{&1}'") |> Enum.join(",")

      execute """
      INSERT INTO category_translations (id, category_id, locale, name, search_translation, search_queries, inserted_at, updated_at)
      SELECT
        gen_random_uuid(),
        id,
        'nl',
        '#{name}',
        '#{search_translation}',
        ARRAY[#{search_queries}]::text[],
        NOW(),
        NOW()
      FROM categories
      WHERE slug = '#{slug}'
      """
    end
  end

  def down do
    execute "DELETE FROM category_translations WHERE locale IN ('es', 'nl')"
  end
end
