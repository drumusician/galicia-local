defmodule GaliciaLocal.Repo.Migrations.CleanUpCategorySearchData do
  use Ecto.Migration

  def up do
    # English search data for each category (keyed by slug for stability)
    english_search_data = %{
      "accountants" => {"accountants", ~s({"accountants","accounting firm","tax advisor","bookkeeper"})},
      "bakeries" => {"bakeries", ~s({"bakeries","bakery","bread shop"})},
      "butchers" => {"butchers", ~s({"butchers","butcher shop","meat shop"})},
      "cafes" => {"cafes", ~s({"cafes","coffee shop","cafe","pastry shop"})},
      "car-services" => {"car services", ~s({"car repair","auto mechanic","garage","car service"})},
      "cider-houses" => {"cider houses", ~s({"cider house","sidrería"})},
      "dentists" => {"dentists", ~s({"dentists","dental clinic","orthodontist"})},
      "doctors" => {"doctors", ~s({"doctors","medical clinic","health center","family doctor"})},
      "electricians" => {"electricians", ~s({"electricians","electrical installations"})},
      "hair-salons" => {"hair salons", ~s({"hair salons","beauty salon","barber shop"})},
      "language-schools" => {"language schools", ~s({"language school","Spanish classes","language courses"})},
      "lawyers" => {"lawyers", ~s({"lawyers","law firm","legal advice","notary"})},
      "markets" => {"markets", ~s({"markets","food market","farmers market"})},
      "plumbers" => {"plumbers", ~s({"plumbers","plumbing","plumber"})},
      "real-estate-agents" => {"real estate agents", ~s({"real estate agents","real estate agency","property for sale"})},
      "restaurants" => {"restaurants", ~s({"restaurants","tapas","seafood restaurant","pizzeria"})},
      "supermarkets" => {"supermarkets", ~s({"supermarkets","grocery store","hypermarket"})},
      "veterinarians" => {"veterinarians", ~s({"veterinarians","veterinary clinic","vet"})},
      "wineries" => {"wineries", ~s({"wineries","wine shop","wine bar"})}
    }

    # 1. Update categories table: change Spanish search data to English
    for {slug, {search_translation, search_queries_literal}} <- english_search_data do
      execute """
      UPDATE categories
      SET search_translation = '#{search_translation}',
          search_queries = '#{search_queries_literal}'
      WHERE slug = '#{slug}'
      """
    end

    # 2. Create English (en) category_translations from the categories table
    execute """
    INSERT INTO category_translations (id, category_id, locale, name, description, search_translation, search_queries, inserted_at, updated_at)
    SELECT gen_random_uuid(), c.id, 'en', c.name, c.description, c.search_translation, c.search_queries, NOW(), NOW()
    FROM categories c
    WHERE NOT EXISTS (
      SELECT 1 FROM category_translations ct
      WHERE ct.category_id = c.id AND ct.locale = 'en'
    )
    """
  end

  def down do
    # Remove English category translations
    execute "DELETE FROM category_translations WHERE locale = 'en'"

    # Restore Spanish search data from es translations
    execute """
    UPDATE categories c
    SET search_translation = ct.search_translation,
        search_queries = ct.search_queries
    FROM category_translations ct
    WHERE ct.category_id = c.id AND ct.locale = 'es'
    """
  end
end
