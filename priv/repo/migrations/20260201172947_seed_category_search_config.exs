defmodule GaliciaLocal.Repo.Migrations.SeedCategorySearchConfig do
  @moduledoc """
  Data migration to populate existing categories with their hardcoded
  search translations, sub-queries, and enrichment hints.
  """
  use Ecto.Migration

  @categories %{
    "lawyers" => %{
      search_translation: "abogados",
      search_queries: ["abogados", "bufete abogados", "asesoría legal", "notaría"],
      enrichment_hints: "Note any specialties relevant to newcomers: immigration law (extranjería), property purchase, NIE/residency procedures, inheritance law."
    },
    "accountants" => %{
      search_translation: "contables",
      search_queries: ["contables", "asesoría fiscal", "gestoría"]
    },
    "real-estate" => %{
      search_translation: "inmobiliarias",
      search_queries: ["inmobiliarias", "agencia inmobiliaria", "venta pisos"],
      enrichment_hints: "Note if this agency has experience helping foreigners buy/rent property. Mention typical areas they cover and property types."
    },
    "doctors" => %{
      search_translation: "medicos",
      search_queries: ["médicos", "clínica médica", "centro de salud", "médico de familia"],
      enrichment_hints: "Note if this is a private clinic or public health center (centro de salud). Mention any specialties and whether they accept private insurance."
    },
    "dentists" => %{
      search_translation: "dentistas",
      search_queries: ["dentistas", "clínica dental", "ortodoncia"]
    },
    "restaurants" => %{
      search_translation: "restaurantes",
      search_queries: ["restaurantes", "tapas", "marisquería", "pizzería", "asador", "sidrería", "pulpería"],
      enrichment_hints: "Note whether this restaurant serves traditional Galician cuisine (pulpo, empanada, marisco, caldo gallego, etc.) vs international food. Highlight local dishes."
    },
    "cafes" => %{
      search_translation: "cafeterias",
      search_queries: ["cafeterías", "café", "pastelería", "chocolatería"]
    },
    "supermarkets" => %{
      search_translation: "supermercados",
      search_queries: ["supermercados", "hipermercado", "tienda alimentación"]
    },
    "plumbers" => %{
      search_translation: "fontaneros",
      search_queries: ["fontaneros", "fontanería", "instalaciones sanitarias"]
    },
    "electricians" => %{
      search_translation: "electricistas",
      search_queries: ["electricistas", "instalaciones eléctricas"]
    },
    "veterinarians" => %{
      search_translation: "veterinarios",
      search_queries: ["veterinarios", "clínica veterinaria"]
    },
    "hair-salons" => %{
      search_translation: "peluquerias",
      search_queries: ["peluquerías", "salón de belleza", "barbería"]
    },
    "car-services" => %{
      search_translation: "talleres",
      search_queries: ["talleres", "taller mecánico", "taller coches", "ITV"]
    },
    "wineries" => %{
      search_translation: "bodegas",
      search_queries: ["bodegas", "vinoteca", "enoteca"]
    },
    "bakeries" => %{
      search_translation: "panaderias",
      search_queries: ["panaderías", "panadería", "horno de pan"]
    },
    "butchers" => %{
      search_translation: "carnicerias",
      search_queries: ["carnicerías", "carnicería"]
    },
    "markets" => %{
      search_translation: "mercados",
      search_queries: ["mercados", "mercado municipal", "mercado de abastos"]
    },
    "language-schools" => %{
      search_translation: "escuela español para extranjeros",
      search_queries: ["academia español extranjeros", "clases español", "escuela gallego", "cursos idiomas español", "escuela oficial idiomas"],
      enrichment_hints: "Pay special attention to what languages this school TEACHES (not just speaks). We primarily want schools teaching Spanish and/or Galician to foreigners. Schools that only teach English are less relevant for our audience. Populate the \"languages_taught\" field with specific languages taught."
    },
    "cider-houses" => %{
      search_queries: ["sidrerías", "sidrería"]
    }
  }

  def up do
    for {slug, config} <- @categories do
      set_clauses = []

      set_clauses =
        if Map.has_key?(config, :search_translation) do
          set_clauses ++ ["search_translation = #{escape(config.search_translation)}"]
        else
          set_clauses
        end

      set_clauses =
        if Map.has_key?(config, :search_queries) and config.search_queries != [] do
          array = Enum.map_join(config.search_queries, ", ", &escape/1)
          set_clauses ++ ["search_queries = ARRAY[#{array}]"]
        else
          set_clauses
        end

      set_clauses =
        if Map.has_key?(config, :enrichment_hints) do
          set_clauses ++ ["enrichment_hints = #{escape(config.enrichment_hints)}"]
        else
          set_clauses
        end

      if set_clauses != [] do
        execute("UPDATE categories SET #{Enum.join(set_clauses, ", ")} WHERE slug = '#{slug}'")
      end
    end
  end

  def down do
    execute("UPDATE categories SET search_translation = NULL, search_queries = '{}', enrichment_hints = NULL")
  end

  defp escape(value) do
    escaped = String.replace(value, "'", "''")
    "'#{escaped}'"
  end
end
