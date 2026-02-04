defmodule GaliciaLocal.Repo.Migrations.MigrateSpanishToTranslationTables do
  use Ecto.Migration

  def up do
    # Migrate Spanish business translations
    execute """
    INSERT INTO business_translations (id, business_id, locale, description, summary, highlights, warnings, integration_tips, cultural_notes, inserted_at, updated_at)
    SELECT
      gen_random_uuid(),
      id,
      'es',
      description_es,
      summary_es,
      COALESCE(highlights_es, '{}'),
      COALESCE(warnings_es, '{}'),
      COALESCE(integration_tips_es, '{}'),
      COALESCE(cultural_notes_es, '{}'),
      NOW(),
      NOW()
    FROM businesses
    WHERE description_es IS NOT NULL
       OR summary_es IS NOT NULL
       OR array_length(highlights_es, 1) > 0
       OR array_length(warnings_es, 1) > 0
       OR array_length(integration_tips_es, 1) > 0
       OR array_length(cultural_notes_es, 1) > 0
    """

    # Also create English translations from the main fields
    execute """
    INSERT INTO business_translations (id, business_id, locale, description, summary, highlights, warnings, integration_tips, cultural_notes, inserted_at, updated_at)
    SELECT
      gen_random_uuid(),
      id,
      'en',
      description,
      summary,
      COALESCE(highlights, '{}'),
      COALESCE(warnings, '{}'),
      COALESCE(integration_tips, '{}'),
      COALESCE(cultural_notes, '{}'),
      NOW(),
      NOW()
    FROM businesses
    WHERE description IS NOT NULL
       OR summary IS NOT NULL
       OR array_length(highlights, 1) > 0
       OR array_length(warnings, 1) > 0
       OR array_length(integration_tips, 1) > 0
       OR array_length(cultural_notes, 1) > 0
    """

    # Migrate Spanish city translations
    execute """
    INSERT INTO city_translations (id, city_id, locale, description, inserted_at, updated_at)
    SELECT
      gen_random_uuid(),
      id,
      'es',
      description_es,
      NOW(),
      NOW()
    FROM cities
    WHERE description_es IS NOT NULL
    """

    # Also create English city translations from the main field
    execute """
    INSERT INTO city_translations (id, city_id, locale, description, inserted_at, updated_at)
    SELECT
      gen_random_uuid(),
      id,
      'en',
      description,
      NOW(),
      NOW()
    FROM cities
    WHERE description IS NOT NULL
    """
  end

  def down do
    execute "DELETE FROM business_translations WHERE locale IN ('es', 'en')"
    execute "DELETE FROM city_translations WHERE locale IN ('es', 'en')"
  end
end
