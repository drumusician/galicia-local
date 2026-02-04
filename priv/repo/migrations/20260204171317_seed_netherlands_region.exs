defmodule GaliciaLocal.Repo.Migrations.SeedNetherlandsRegion do
  use Ecto.Migration

  def up do
    # Insert Netherlands region (skip if already exists)
    execute """
    INSERT INTO regions (id, name, slug, country_code, default_locale, supported_locales, timezone, active, settings, inserted_at, updated_at)
    SELECT
      gen_random_uuid(),
      'Netherlands',
      'netherlands',
      'NL',
      'en',
      ARRAY['en', 'nl']::text[],
      'Europe/Amsterdam',
      true,
      '{}',
      NOW(),
      NOW()
    WHERE NOT EXISTS (SELECT 1 FROM regions WHERE slug = 'netherlands')
    """

    # Insert major Dutch cities (skip any that already exist)
    execute """
    WITH nl_region AS (SELECT id FROM regions WHERE slug = 'netherlands')
    INSERT INTO cities (id, name, slug, province, latitude, longitude, population, featured, region_id, inserted_at, updated_at)
    SELECT
      gen_random_uuid(),
      c.name,
      c.slug,
      c.province,
      c.latitude,
      c.longitude,
      c.population,
      c.featured,
      nl_region.id,
      NOW(),
      NOW()
    FROM nl_region, (VALUES
      ('Amsterdam', 'amsterdam', 'Noord-Holland', 52.3676, 4.9041, 905234, true),
      ('Rotterdam', 'rotterdam', 'Zuid-Holland', 51.9244, 4.4777, 656050, true),
      ('Den Haag', 'den-haag', 'Zuid-Holland', 52.0705, 4.3007, 548573, true),
      ('Utrecht', 'utrecht', 'Utrecht', 52.0907, 5.1214, 361966, true),
      ('Eindhoven', 'eindhoven', 'Noord-Brabant', 51.4416, 5.4697, 238478, false),
      ('Groningen', 'groningen', 'Groningen', 53.2194, 6.5665, 234249, false),
      ('Tilburg', 'tilburg', 'Noord-Brabant', 51.5555, 5.0913, 224702, false),
      ('Almere', 'almere', 'Flevoland', 52.3508, 5.2647, 218096, false),
      ('Breda', 'breda', 'Noord-Brabant', 51.5719, 4.7683, 184403, false),
      ('Nijmegen', 'nijmegen', 'Gelderland', 51.8426, 5.8546, 179073, false),
      ('Arnhem', 'arnhem', 'Gelderland', 51.9851, 5.8987, 164096, false),
      ('Haarlem', 'haarlem', 'Noord-Holland', 52.3874, 4.6462, 162902, false),
      ('Enschede', 'enschede', 'Overijssel', 52.2215, 6.8937, 160854, false),
      ('Maastricht', 'maastricht', 'Limburg', 50.8514, 5.6910, 121565, false),
      ('Leiden', 'leiden', 'Zuid-Holland', 52.1601, 4.4970, 126269, false),
      ('Delft', 'delft', 'Zuid-Holland', 52.0116, 4.3571, 104804, false)
    ) AS c(name, slug, province, latitude, longitude, population, featured)
    WHERE NOT EXISTS (
      SELECT 1 FROM cities
      WHERE cities.slug = c.slug
      AND cities.region_id = nl_region.id
    )
    """
  end

  def down do
    # Delete cities first (foreign key constraint)
    execute """
    DELETE FROM cities WHERE region_id = (SELECT id FROM regions WHERE slug = 'netherlands')
    """

    # Delete Netherlands region
    execute """
    DELETE FROM regions WHERE slug = 'netherlands'
    """
  end
end
