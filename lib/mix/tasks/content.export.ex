defmodule Mix.Tasks.Content.Export do
  @shortdoc "Export businesses as JSON for processing by Claude Code"
  @moduledoc """
  Exports business data as JSON files for translation or enrichment
  by Claude Code agents (no API calls needed — uses your Max plan).

  ## Translation Export

      mix content.export translations --locale es
      mix content.export translations --locale nl --limit 50
      mix content.export translations --locale es --region galicia --batch-size 25

  Exports enriched businesses missing translations for the given locale.

  ## Enrichment Export

      mix content.export enrichments
      mix content.export enrichments --limit 50 --region galicia

  Exports unenriched businesses with their reviews and context data.

  ## Options

      --locale LOCALE       Target locale for translations (es or nl)
      --limit N             Max businesses total
      --batch-size N        Businesses per output file (default: 25 for translations, 10 for enrichments)
      --region REGION       Filter by region slug (galicia or netherlands)
      --output-dir DIR      Output directory (default: tmp/content_batches)
  """

  use Mix.Task

  import Ecto.Query

  @output_dir "tmp/content_batches"

  @impl Mix.Task
  def run(argv) do
    {:ok, _} = Application.ensure_all_started(:postgrex)
    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    {:ok, _} = GaliciaLocal.Repo.start_link()

    case argv do
      ["translations" | rest] -> export_translations(rest)
      ["enrichments" | rest] -> export_enrichments(rest)
      _ -> Mix.raise("Usage: mix content.export [translations|enrichments] [options]")
    end
  end

  # --- Translation Export ---

  defp export_translations(argv) do
    {opts, _, _} =
      OptionParser.parse(argv,
        switches: [locale: :string, limit: :integer, batch_size: :integer, region: :string, output_dir: :string]
      )

    locale = opts[:locale] || Mix.raise("--locale is required (es or nl)")
    limit = opts[:limit]
    batch_size = opts[:batch_size] || 25
    region_slug = opts[:region]
    output_dir = opts[:output_dir] || @output_dir

    unless locale in ["es", "nl"] do
      Mix.raise("--locale must be 'es' or 'nl'")
    end

    region_id = resolve_region_id(region_slug)
    missing_ids = GaliciaLocal.Directory.TranslationStatus.missing_business_ids(locale, region_id)

    missing_ids = if limit, do: Enum.take(missing_ids, limit), else: missing_ids
    total = length(missing_ids)

    locale_name = %{"es" => "Spanish", "nl" => "Dutch"}[locale]
    Mix.shell().info("Found #{total} businesses missing #{locale_name} translations")

    if total == 0 do
      Mix.shell().info("Nothing to export!")
    else
      batches = Enum.chunk_every(missing_ids, batch_size)
      batch_dir = Path.join(output_dir, "translate_#{locale}")
      File.mkdir_p!(batch_dir)

      # Clear old batches
      batch_dir |> File.ls!() |> Enum.each(&File.rm!(Path.join(batch_dir, &1)))

      Enum.each(Enum.with_index(batches, 1), fn {batch_ids, batch_num} ->
        businesses = load_businesses_for_translation(batch_ids)

        data = %{
          type: "translation",
          target_locale: locale,
          batch: batch_num,
          total_batches: length(batches),
          count: length(businesses),
          businesses: businesses
        }

        file = Path.join(batch_dir, "batch_#{String.pad_leading("#{batch_num}", 3, "0")}.json")
        File.write!(file, Jason.encode!(data, pretty: true))
        Mix.shell().info("  Wrote #{file} (#{length(businesses)} businesses)")
      end)

      Mix.shell().info("")
      Mix.shell().info("Exported #{total} businesses in #{length(batches)} batches to #{batch_dir}/")
      Mix.shell().info("")
      Mix.shell().info("Next: Process with Claude Code agents, then import with:")
      Mix.shell().info("  mix content.import translations --dir #{batch_dir}")
    end
  end

  defp load_businesses_for_translation(ids) do
    placeholders = ids |> Enum.with_index(1) |> Enum.map_join(", ", fn {_, i} -> "$#{i}::uuid" end)
    params = Enum.map(ids, &Ecto.UUID.dump!/1)

    %{rows: rows} =
      GaliciaLocal.Repo.query!("""
      SELECT b.id::text, b.name, b.description, b.summary,
             b.highlights, b.warnings, b.integration_tips, b.cultural_notes
      FROM businesses b
      WHERE b.id IN (#{placeholders})
      """, params)

    Enum.map(rows, fn [id, name, description, summary, highlights, warnings, tips, notes] ->
      %{
        id: id,
        name: name,
        description: description,
        summary: summary,
        highlights: highlights || [],
        warnings: warnings || [],
        integration_tips: tips || [],
        cultural_notes: notes || []
      }
    end)
  end

  # --- Enrichment Export ---

  defp export_enrichments(argv) do
    {opts, _, _} =
      OptionParser.parse(argv,
        switches: [limit: :integer, batch_size: :integer, region: :string, output_dir: :string]
      )

    limit = opts[:limit]
    batch_size = opts[:batch_size] || 10
    region_slug = opts[:region]
    output_dir = opts[:output_dir] || @output_dir

    region_id = resolve_region_id(region_slug)

    # Get all category slugs for the prompt
    all_category_slugs = get_all_category_slugs()

    businesses = find_unenriched(region_id, limit)
    total = length(businesses)

    Mix.shell().info("Found #{total} businesses needing enrichment")

    if total == 0 do
      Mix.shell().info("Nothing to export!")
    else
      batches = Enum.chunk_every(businesses, batch_size)
      batch_dir = Path.join(output_dir, "enrich")
      File.mkdir_p!(batch_dir)

      # Clear old batches
      batch_dir |> File.ls!() |> Enum.each(&File.rm!(Path.join(batch_dir, &1)))

      Enum.each(Enum.with_index(batches, 1), fn {batch, batch_num} ->
        data = %{
          type: "enrichment",
          batch: batch_num,
          total_batches: length(batches),
          count: length(batch),
          all_category_slugs: all_category_slugs,
          businesses: batch
        }

        file = Path.join(batch_dir, "batch_#{String.pad_leading("#{batch_num}", 3, "0")}.json")
        File.write!(file, Jason.encode!(data, pretty: true))
        Mix.shell().info("  Wrote #{file} (#{length(batch)} businesses)")
      end)

      Mix.shell().info("")
      Mix.shell().info("Exported #{total} businesses in #{length(batches)} batches to #{batch_dir}/")
      Mix.shell().info("")
      Mix.shell().info("Next: Process with Claude Code agents, then import with:")
      Mix.shell().info("  mix content.import enrichments --dir #{batch_dir}")
    end
  end

  defp find_unenriched(region_id, limit) do
    region_clause = if region_id, do: "AND b.region_id = '#{region_id}'", else: ""
    limit_clause = if limit, do: "LIMIT #{limit}", else: ""

    %{rows: rows} =
      GaliciaLocal.Repo.query!("""
      SELECT
        b.id::text,
        b.name,
        c.name as category_name,
        c.slug as category_slug,
        ci.name as city_name,
        r.slug as region_slug,
        b.address,
        b.phone,
        b.website,
        b.rating,
        b.review_count,
        b.raw_data,
        ct.enrichment_hints
      FROM businesses b
      LEFT JOIN categories c ON c.id = b.category_id
      LEFT JOIN cities ci ON ci.id = b.city_id
      LEFT JOIN regions r ON r.id = b.region_id
      LEFT JOIN category_translations ct ON ct.category_id = c.id AND ct.locale = r.default_locale
      WHERE b.status IN ('pending', 'researching', 'researched')
        AND b.summary IS NULL
        #{region_clause}
      ORDER BY
        CASE WHEN b.raw_data->>'reviews_text' IS NOT NULL THEN 0 ELSE 1 END,
        b.rating DESC NULLS LAST
      #{limit_clause}
      """)

    Enum.map(rows, fn [id, name, category, category_slug, city, region, address, phone, website, rating, review_count, raw_data, hints] ->
      reviews_text = extract_reviews(raw_data)
      place_types = extract_place_types(raw_data)

      %{
        id: id,
        name: name,
        category: category || "Unknown",
        category_slug: category_slug,
        city: city || "Unknown",
        region: region || "galicia",
        address: address,
        phone: phone,
        website: website,
        rating: if(is_struct(rating, Decimal), do: Decimal.to_float(rating), else: rating),
        review_count: review_count || 0,
        reviews_text: reviews_text,
        place_types: place_types,
        enrichment_hints: hints
      }
    end)
  end

  defp extract_reviews(nil), do: "No reviews available."
  defp extract_reviews(%{"reviews_text" => text}) when is_binary(text) and text != "", do: text

  defp extract_reviews(%{"reviews" => reviews}) when is_list(reviews) and length(reviews) > 0 do
    reviews
    |> Enum.take(10)
    |> Enum.map(fn r ->
      lang = r["language"] || "unknown"
      author = r["author"] || "Anonymous"
      rating = r["rating"] || "?"
      text = r["text"] || ""
      "[#{lang}] #{author} (#{rating}*): #{text}"
    end)
    |> Enum.join("\n---\n")
  end

  defp extract_reviews(_), do: "No reviews available."

  defp extract_place_types(%{"types" => types}) when is_list(types), do: Enum.take(types, 5)
  defp extract_place_types(_), do: []

  defp get_all_category_slugs do
    %{rows: rows} =
      GaliciaLocal.Repo.query!("SELECT slug FROM categories ORDER BY slug")

    Enum.map(rows, fn [slug] -> slug end)
  end

  defp resolve_region_id(nil), do: nil

  defp resolve_region_id(slug) do
    case GaliciaLocal.Repo.one(
           from(r in "regions", where: r.slug == ^slug, select: r.id)
         ) do
      nil -> Mix.raise("Region not found: #{slug}")
      id -> Ecto.UUID.cast!(id)
    end
  end
end
