defmodule GaliciaLocal.Repo.Migrations.SeedDutchCategoryTranslations do
  use Ecto.Migration

  @dutch_translations [
    # Expat Essentials (Priority 1)
    {"lawyers", "Advocaten", "advocaten", ~w(advocaten advocatenkantoor juridisch\ advies notaris)},
    {"accountants", "Accountants", "accountants", ~w(accountant boekhouder belastingadviseur administratiekantoor)},
    {"doctors", "Artsen", "huisarts", ~w(huisarts dokter medisch\ centrum gezondheidscentrum)},
    {"dentists", "Tandartsen", "tandarts", ~w(tandarts tandartspraktijk mondhygiënist)},
    {"language-schools", "Taalscholen", "taalschool", ~w(taalschool Nederlands\ leren inburgeringscursus NT2)},
    {"real-estate", "Makelaars", "makelaar", ~w(makelaar vastgoed huurwoning koopwoning woningaanbod)},

    # Daily Life (Priority 2)
    {"supermarkets", "Supermarkten", "supermarkt", ~w(supermarkt Albert\ Heijn Jumbo Lidl boodschappen)},
    {"bakeries", "Bakkerijen", "bakker", ~w(bakker bakkerij brood banketbakker)},
    {"butchers", "Slagerijen", "slager", ~w(slager slagerij vleeswinkel)},
    {"markets", "Markten", "markt", ~w(markt weekmarkt boerenmarkt versmarkt)},
    {"hair-salons", "Kappers", "kapper", ~w(kapper kapsalon barbier herenkapper dameskapper)},

    # Lifestyle (Priority 3)
    {"restaurants", "Restaurants", "restaurant", ~w(restaurant eetcafe bistro brasserie)},
    {"cafes", "Cafés", "cafe", ~w(cafe koffiebar koffiezaak lunchroom)},
    {"cider-houses", "Bruine Cafés", "bruin\ cafe", ~w(bruin\ cafe kroeg grand\ cafe eetcafe)},
    {"wineries", "Wijnwinkels", "wijnwinkel", ~w(wijnwinkel slijterij wijnhandel)},

    # Practical (Priority 4)
    {"car-services", "Garages", "garage", ~w(garage automonteur APK\ keuring autoservice)},
    {"electricians", "Elektriciens", "elektricien", ~w(elektricien elektrische\ installatie)},
    {"plumbers", "Loodgieters", "loodgieter", ~w(loodgieter installateur sanitair)},
    {"veterinarians", "Dierenartsen", "dierenarts", ~w(dierenarts dierenkliniek huisdierenzorg)}
  ]

  def up do
    for {slug, name, search_translation, search_queries} <- @dutch_translations do
      # Format search_queries as PostgreSQL array
      queries_array = search_queries
        |> Enum.map(&"'#{String.replace(&1, "'", "''")}'")
        |> Enum.join(", ")

      execute """
      INSERT INTO category_translations (id, category_id, locale, name, search_translation, search_queries, inserted_at, updated_at)
      SELECT
        gen_random_uuid(),
        c.id,
        'nl',
        '#{String.replace(name, "'", "''")}',
        '#{String.replace(search_translation, "'", "''")}',
        ARRAY[#{queries_array}]::text[],
        NOW(),
        NOW()
      FROM categories c
      WHERE c.slug = '#{slug}'
      ON CONFLICT (category_id, locale) DO UPDATE SET
        name = EXCLUDED.name,
        search_translation = EXCLUDED.search_translation,
        search_queries = EXCLUDED.search_queries,
        updated_at = NOW()
      """
    end
  end

  def down do
    execute "DELETE FROM category_translations WHERE locale = 'nl'"
  end
end
