defmodule Mix.Tasks.Content.Import do
  @shortdoc "Import processed translations/enrichments from Claude Code JSON"
  @moduledoc """
  Reads JSON result files produced by Claude Code agents and writes
  translations or enrichments to the database.

  ## Import Translations

      mix content.import translations --dir tmp/content_batches/translate_es
      mix content.import translations --file tmp/content_batches/translate_es/batch_001_result.json

  Expected JSON format for translations:
  ```json
  {
    "target_locale": "es",
    "translations": [
      {
        "business_id": "uuid",
        "description": "Translated description",
        "summary": "Translated summary",
        "highlights": ["translated highlight"],
        "warnings": ["translated warning"],
        "integration_tips": ["translated tip"],
        "cultural_notes": ["translated note"]
      }
    ]
  }
  ```

  ## Import Enrichments

      mix content.import enrichments --dir tmp/content_batches/enrich
      mix content.import enrichments --file tmp/content_batches/enrich/batch_001_result.json

  Expected JSON format for enrichments:
  ```json
  {
    "enrichments": [
      {
        "business_id": "uuid",
        "description": "2-3 sentence description",
        "summary": "One-liner",
        "local_gem_score": 0.8,
        "newcomer_friendly_score": 0.7,
        "speaks_english": false,
        "speaks_english_confidence": 0.3,
        "languages_spoken": ["es", "gl"],
        "integration_tips": ["tip"],
        "cultural_notes": ["note"],
        "service_specialties": ["spec"],
        "highlights": ["highlight"],
        "warnings": ["warning"],
        "sentiment_summary": "...",
        "review_insights": {},
        "quality_score": 0.7,
        "category_fit_score": 0.9,
        "suggested_category_slug": null
      }
    ]
  }
  ```

  ## Options

      --dir DIR     Process all *_result.json files in directory
      --file FILE   Process a single result file
      --dry-run     Show what would be imported without writing to DB
  """

  use Mix.Task

  require Logger

  @impl Mix.Task
  def run(argv) do
    {:ok, _} = Application.ensure_all_started(:postgrex)
    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    {:ok, _} = Application.ensure_all_started(:ash)
    {:ok, _} = GaliciaLocal.Repo.start_link()

    case argv do
      ["translations" | rest] -> import_translations(rest)
      ["city_translations" | rest] -> import_city_translations(rest)
      ["enrichments" | rest] -> import_enrichments(rest)
      _ -> Mix.raise("Usage: mix content.import [translations|city_translations|enrichments] [--dir DIR | --file FILE]")
    end
  end

  # --- Translation Import ---

  defp import_translations(argv) do
    {opts, _, _} =
      OptionParser.parse(argv, switches: [dir: :string, file: :string, dry_run: :boolean])

    dry_run? = opts[:dry_run] || false
    files = resolve_result_files(opts)

    Mix.shell().info("Processing #{length(files)} translation result file(s)")

    {total_ok, total_fail} =
      Enum.reduce(files, {0, 0}, fn file, {ok, fail} ->
        Mix.shell().info("")
        Mix.shell().info("Reading #{file}...")

        data = file |> File.read!() |> Jason.decode!()
        locale = data["target_locale"]
        translations = data["translations"] || []

        Mix.shell().info("  #{length(translations)} translations for locale '#{locale}'")

        if dry_run? do
          Enum.each(Enum.take(translations, 3), fn t ->
            Mix.shell().info("    #{t["business_id"]}: #{String.slice(t["summary"] || "", 0, 60)}...")
          end)

          {ok + length(translations), fail}
        else
          {batch_ok, batch_fail} =
            Enum.reduce(translations, {0, 0}, fn t, {s, f} ->
              case upsert_translation(t, locale) do
                :ok -> {s + 1, f}
                :error -> {s, f + 1}
              end
            end)

          Mix.shell().info("  Done: #{batch_ok} saved, #{batch_fail} failed")
          {ok + batch_ok, fail + batch_fail}
        end
      end)

    Mix.shell().info("")
    prefix = if dry_run?, do: "[DRY RUN] Would import", else: "Imported"
    Mix.shell().info("#{prefix} #{total_ok} translations (#{total_fail} failures)")
  end

  defp upsert_translation(t, locale) do
    alias GaliciaLocal.Directory.BusinessTranslation

    params = %{
      business_id: t["business_id"],
      locale: locale,
      description: t["description"],
      summary: t["summary"],
      highlights: t["highlights"] || [],
      warnings: t["warnings"] || [],
      integration_tips: t["integration_tips"] || [],
      cultural_notes: t["cultural_notes"] || [],
      content_source: "ai_generated",
      source_locale: "en"
    }

    case BusinessTranslation.upsert(params) do
      {:ok, _} -> :ok
      {:error, reason} ->
        Logger.error("Failed to upsert translation for #{t["business_id"]}: #{inspect(reason)}")
        :error
    end
  end

  # --- City Translation Import ---

  defp import_city_translations(argv) do
    {opts, _, _} =
      OptionParser.parse(argv, switches: [dir: :string, file: :string, dry_run: :boolean])

    dry_run? = opts[:dry_run] || false
    files = resolve_result_files(opts)

    Mix.shell().info("Processing #{length(files)} city translation result file(s)")

    {total_ok, total_fail} =
      Enum.reduce(files, {0, 0}, fn file, {ok, fail} ->
        Mix.shell().info("")
        Mix.shell().info("Reading #{file}...")

        data = file |> File.read!() |> Jason.decode!()
        locale = data["target_locale"]
        translations = data["translations"] || []

        Mix.shell().info("  #{length(translations)} city translations for locale '#{locale}'")

        if dry_run? do
          Enum.each(Enum.take(translations, 3), fn t ->
            Mix.shell().info("    #{t["city_id"]}: #{String.slice(t["description"] || "", 0, 60)}...")
          end)

          {ok + length(translations), fail}
        else
          {batch_ok, batch_fail} =
            Enum.reduce(translations, {0, 0}, fn t, {s, f} ->
              case upsert_city_translation(t, locale) do
                :ok -> {s + 1, f}
                :error -> {s, f + 1}
              end
            end)

          Mix.shell().info("  Done: #{batch_ok} saved, #{batch_fail} failed")
          {ok + batch_ok, fail + batch_fail}
        end
      end)

    Mix.shell().info("")
    prefix = if dry_run?, do: "[DRY RUN] Would import", else: "Imported"
    Mix.shell().info("#{prefix} #{total_ok} city translations (#{total_fail} failures)")
  end

  defp upsert_city_translation(t, locale) do
    alias GaliciaLocal.Directory.CityTranslation

    params = %{
      city_id: t["city_id"],
      locale: locale,
      description: t["description"]
    }

    case CityTranslation.upsert(params) do
      {:ok, _} -> :ok
      {:error, reason} ->
        Logger.error("Failed to upsert city translation for #{t["city_id"]}: #{inspect(reason)}")
        :error
    end
  end

  # --- Enrichment Import ---

  defp import_enrichments(argv) do
    {opts, _, _} =
      OptionParser.parse(argv, switches: [dir: :string, file: :string, dry_run: :boolean])

    dry_run? = opts[:dry_run] || false
    files = resolve_result_files(opts)

    Mix.shell().info("Processing #{length(files)} enrichment result file(s)")

    {total_ok, total_fail} =
      Enum.reduce(files, {0, 0}, fn file, {ok, fail} ->
        Mix.shell().info("")
        Mix.shell().info("Reading #{file}...")

        data = file |> File.read!() |> Jason.decode!()
        enrichments = data["enrichments"] || []

        Mix.shell().info("  #{length(enrichments)} enrichments")

        if dry_run? do
          Enum.each(Enum.take(enrichments, 3), fn e ->
            Mix.shell().info("    #{e["business_id"]}: #{e["summary"]}")
          end)

          {ok + length(enrichments), fail}
        else
          {batch_ok, batch_fail} =
            Enum.reduce(enrichments, {0, 0}, fn e, {s, f} ->
              case apply_enrichment(e) do
                :ok -> {s + 1, f}
                :error -> {s, f + 1}
              end
            end)

          Mix.shell().info("  Done: #{batch_ok} saved, #{batch_fail} failed")
          {ok + batch_ok, fail + batch_fail}
        end
      end)

    Mix.shell().info("")
    prefix = if dry_run?, do: "[DRY RUN] Would import", else: "Imported"
    Mix.shell().info("#{prefix} #{total_ok} enrichments (#{total_fail} failures)")
  end

  defp apply_enrichment(e) do
    business_id = e["business_id"]

    # Build the update SQL directly for reliability
    sets = build_enrichment_sets(e)

    if sets == "" do
      Logger.warning("No enrichment data for #{business_id}")
      :error
    else
      sql = """
      UPDATE businesses SET
        #{sets},
        status = 'enriched',
        last_enriched_at = NOW(),
        updated_at = NOW()
      WHERE id = $1::uuid AND summary IS NULL
      """

      case GaliciaLocal.Repo.query(sql, [Ecto.UUID.dump!(business_id)]) do
        {:ok, %{num_rows: 1}} -> :ok
        {:ok, %{num_rows: 0}} ->
          Logger.info("Skipped #{business_id} (already enriched or not found)")
          :ok
        {:error, reason} ->
          Logger.error("Failed to enrich #{business_id}: #{inspect(reason)}")
          :error
      end
    end
  end

  defp build_enrichment_sets(e) do
    fields = [
      string_set("description", e["description"]),
      string_set("summary", e["summary"]),
      bool_set("speaks_english", e["speaks_english"]),
      decimal_set("speaks_english_confidence", e["speaks_english_confidence"]),
      decimal_set("newcomer_friendly_score", e["newcomer_friendly_score"]),
      decimal_set("local_gem_score", e["local_gem_score"]),
      decimal_set("quality_score", e["quality_score"]),
      decimal_set("category_fit_score", e["category_fit_score"]),
      string_set("suggested_category_slug", e["suggested_category_slug"]),
      string_set("sentiment_summary", e["sentiment_summary"]),
      array_set("highlights", e["highlights"]),
      array_set("warnings", e["warnings"]),
      array_set("integration_tips", e["integration_tips"]),
      array_set("cultural_notes", e["cultural_notes"]),
      array_set("service_specialties", e["service_specialties"]),
      languages_set("languages_spoken", e["languages_spoken"]),
      languages_set("languages_taught", e["languages_taught"]),
      jsonb_set("review_insights", e["review_insights"]),
      # Backwards compatibility
      decimal_set("expat_friendly_score", e["newcomer_friendly_score"]),
      array_set("expat_tips", e["integration_tips"])
    ]

    fields
    |> Enum.reject(&is_nil/1)
    |> Enum.join(",\n  ")
  end

  defp string_set(_col, nil), do: nil
  defp string_set(col, value) when is_binary(value) do
    escaped = String.replace(value, "'", "''")
    "#{col} = '#{escaped}'"
  end

  defp bool_set(_col, nil), do: nil
  defp bool_set(col, value), do: "#{col} = #{value}"

  defp decimal_set(_col, nil), do: nil
  defp decimal_set(col, value) when is_number(value), do: "#{col} = #{value}"

  defp array_set(_col, nil), do: nil
  defp array_set(col, []), do: "#{col} = ARRAY[]::text[]"
  defp array_set(col, items) when is_list(items) do
    elements =
      items
      |> Enum.map(fn item ->
        escaped = item |> to_string() |> String.replace("'", "''")
        "'#{escaped}'"
      end)
      |> Enum.join(", ")

    "#{col} = ARRAY[#{elements}]"
  end

  defp languages_set(_col, nil), do: nil
  defp languages_set(col, []), do: "#{col} = ARRAY[]::varchar[]"
  defp languages_set(col, langs) when is_list(langs) do
    elements =
      langs
      |> Enum.map(fn lang ->
        code = normalize_language(lang)
        "'#{code}'"
      end)
      |> Enum.join(", ")

    "#{col} = ARRAY[#{elements}]::varchar[]"
  end

  defp normalize_language(lang) when is_binary(lang) do
    case String.downcase(lang) do
      "spanish" -> "es"
      "english" -> "en"
      "galician" -> "gl"
      "galego" -> "gl"
      "portuguese" -> "pt"
      "german" -> "de"
      "french" -> "fr"
      "dutch" -> "nl"
      "italian" -> "it"
      other -> String.slice(other, 0, 2)
    end
  end
  defp normalize_language(lang), do: to_string(lang)

  defp jsonb_set(_col, nil), do: nil
  defp jsonb_set(col, value) when is_map(value) do
    escaped = value |> Jason.encode!() |> String.replace("'", "''")
    "#{col} = '#{escaped}'::jsonb"
  end

  # --- Helpers ---

  defp resolve_result_files(opts) do
    cond do
      opts[:file] ->
        file = opts[:file]
        unless File.exists?(file), do: Mix.raise("File not found: #{file}")
        [file]

      opts[:dir] ->
        dir = opts[:dir]
        unless File.dir?(dir), do: Mix.raise("Directory not found: #{dir}")

        dir
        |> File.ls!()
        |> Enum.filter(&String.ends_with?(&1, "_result.json"))
        |> Enum.sort()
        |> Enum.map(&Path.join(dir, &1))
        |> case do
          [] -> Mix.raise("No *_result.json files found in #{dir}")
          files -> files
        end

      true ->
        Mix.raise("Provide --dir or --file")
    end
  end
end
