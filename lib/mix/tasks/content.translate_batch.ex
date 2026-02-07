defmodule Mix.Tasks.Content.TranslateBatch do
  @shortdoc "Batch-translate missing business and city translations via DeepL"
  @moduledoc """
  Finds businesses and cities missing translations for a given locale and translates them
  using DeepL in controlled batches.

  Uses the existing `TranslateWorker` logic to translate content fields
  (description, summary, highlights, warnings, integration_tips, cultural_notes).

  Usage:

      mix content.translate_batch --locale es
      mix content.translate_batch --locale nl --limit 100
      mix content.translate_batch --locale es --limit 50 --sleep 2
      mix content.translate_batch --locale nl --dry-run
      mix content.translate_batch --locale nl --type cities
      mix content.translate_batch --locale nl --type businesses

  Options:

      --locale LOCALE   Target locale (required: "es" or "nl")
      --limit N         Max items to process (default: all)
      --sleep SECONDS   Delay between batches of 10 (default: 1)
      --dry-run         Show what would be translated without making API calls
      --region REGION   Filter by region slug ("galicia" or "netherlands")
      --type TYPE       Entity type to translate: "businesses", "cities", or "all" (default: "all")
  """

  use Mix.Task

  require Logger

  @impl Mix.Task
  def run(argv) do
    {:ok, _} = Application.ensure_all_started(:postgrex)
    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    {:ok, _} = Application.ensure_all_started(:req)
    {:ok, _} = GaliciaLocal.Repo.start_link()

    {opts, _, _} =
      OptionParser.parse(argv,
        switches: [locale: :string, limit: :integer, sleep: :integer, dry_run: :boolean, region: :string, type: :string]
      )

    locale = opts[:locale] || Mix.raise("--locale is required (es or nl)")
    limit = opts[:limit]
    sleep_seconds = opts[:sleep] || 1
    dry_run? = opts[:dry_run] || false
    region_slug = opts[:region]
    entity_type = opts[:type] || "all"

    unless locale in ["es", "nl"] do
      Mix.raise("--locale must be 'es' or 'nl', got: #{locale}")
    end

    unless entity_type in ["all", "businesses", "cities"] do
      Mix.raise("--type must be 'all', 'businesses', or 'cities', got: #{entity_type}")
    end

    region_id = resolve_region_id(region_slug)
    locale_name = %{"es" => "Spanish", "nl" => "Dutch"}[locale]

    if entity_type in ["all", "cities"] do
      translate_cities(locale, locale_name, region_id, limit, sleep_seconds, dry_run?)
    end

    if entity_type in ["all", "businesses"] do
      translate_businesses(locale, locale_name, region_id, limit, sleep_seconds, dry_run?)
    end
  end

  defp translate_cities(locale, locale_name, region_id, limit, sleep_seconds, dry_run?) do
    missing_ids = GaliciaLocal.Directory.TranslationStatus.missing_city_ids(locale, region_id)

    missing_ids =
      if limit do
        Enum.take(missing_ids, limit)
      else
        missing_ids
      end

    total = length(missing_ids)

    Mix.shell().info("")
    Mix.shell().info("=== Cities ===")
    Mix.shell().info("Found #{total} cities missing #{locale_name} translations")

    if dry_run? do
      Mix.shell().info("[DRY RUN] Would translate #{total} cities to #{locale_name}")
      estimate_cost(total, :city)
    else
      if total == 0 do
        Mix.shell().info("Nothing to translate!")
      else
        estimate_cost(total, :city)
        Mix.shell().info("Starting city translation...")

        results = process_city_translations(missing_ids, locale, sleep_seconds)

        successes = Enum.count(results, fn {_, status} -> status == :ok end)
        failures = Enum.count(results, fn {_, status} -> status != :ok end)

        Mix.shell().info("")
        Mix.shell().info("Cities done! #{successes} translated, #{failures} failed out of #{total}")
      end
    end
  end

  defp translate_businesses(locale, locale_name, region_id, limit, sleep_seconds, dry_run?) do
    missing_ids = GaliciaLocal.Directory.TranslationStatus.missing_business_ids(locale, region_id)

    missing_ids =
      if limit do
        Enum.take(missing_ids, limit)
      else
        missing_ids
      end

    total = length(missing_ids)

    Mix.shell().info("")
    Mix.shell().info("=== Businesses ===")
    Mix.shell().info("Found #{total} businesses missing #{locale_name} translations")

    if dry_run? do
      Mix.shell().info("[DRY RUN] Would translate #{total} businesses to #{locale_name}")

      missing_ids
      |> Enum.take(5)
      |> Enum.each(fn id ->
        Mix.shell().info("  #{id}")
      end)

      if total > 5 do
        Mix.shell().info("  ... and #{total - 5} more")
      end

      estimate_cost(total)
    else
      if total == 0 do
        Mix.shell().info("Nothing to translate!")
      else
        estimate_cost(total)
        Mix.shell().info("Starting business translation...")
        Mix.shell().info("")

        results = process_translations(missing_ids, locale, sleep_seconds)

        successes = Enum.count(results, fn {_, status} -> status == :ok end)
        failures = Enum.count(results, fn {_, status} -> status != :ok end)

        Mix.shell().info("")
        Mix.shell().info("Businesses done! #{successes} translated, #{failures} failed out of #{total}")
      end
    end
  end

  defp process_city_translations(ids, locale, sleep_seconds) do
    total = length(ids)

    ids
    |> Enum.with_index(1)
    |> Enum.map(fn {id, index} ->
      if rem(index, 10) == 1 and index > 1 do
        Mix.shell().info("  (sleeping #{sleep_seconds}s between batches...)")
        Process.sleep(sleep_seconds * 1000)
      end

      result = translate_one_city(id, locale)

      status_char = if result == :ok, do: ".", else: "x"

      if rem(index, 50) == 0 or index == total do
        Mix.shell().info("  [#{index}/#{total}] #{status_char}")
      else
        IO.write(status_char)
      end

      {id, result}
    end)
  end

  defp translate_one_city(city_id, locale) do
    alias GaliciaLocal.AI.DeepL
    alias GaliciaLocal.Directory.{City, CityTranslation}

    case City.get_by_id(city_id) do
      {:ok, city} ->
        if non_empty?(city.description) do
          case DeepL.translate(city.description, locale, source_lang: "en") do
            {:ok, translated} ->
              case CityTranslation.upsert(%{
                city_id: city.id,
                locale: locale,
                description: translated
              }) do
                {:ok, _} -> :ok
                {:error, reason} ->
                  Logger.error("Failed to save city translation for #{city_id}: #{inspect(reason)}")
                  {:error, reason}
              end

            {:error, reason} ->
              Logger.error("DeepL failed for city #{city_id}: #{inspect(reason)}")
              {:error, reason}
          end
        else
          :ok
        end

      {:error, _} ->
        Logger.warning("City not found: #{city_id}")
        {:error, :not_found}
    end
  end

  defp process_translations(ids, locale, sleep_seconds) do
    total = length(ids)

    ids
    |> Enum.with_index(1)
    |> Enum.map(fn {id, index} ->
      if rem(index, 10) == 1 and index > 1 do
        Mix.shell().info("  (sleeping #{sleep_seconds}s between batches...)")
        Process.sleep(sleep_seconds * 1000)
      end

      result = translate_one(id, locale)

      status_char = if result == :ok, do: ".", else: "x"

      if rem(index, 50) == 0 or index == total do
        Mix.shell().info("  [#{index}/#{total}] #{status_char}")
      else
        IO.write(status_char)
      end

      {id, result}
    end)
  end

  defp translate_one(business_id, locale) do
    alias GaliciaLocal.AI.DeepL
    alias GaliciaLocal.Directory.{Business, BusinessTranslation}

    case Business.get_by_id(business_id) do
      {:ok, business} ->
        fields = collect_translatable_fields(business)

        if Enum.empty?(fields) do
          :ok
        else
          case translate_fields(fields, locale) do
            {:ok, translated} ->
              params =
                Map.merge(translated, %{
                  business_id: business.id,
                  locale: locale,
                  content_source: "ai_generated",
                  source_locale: "en"
                })

              case BusinessTranslation.upsert(params) do
                {:ok, _} -> :ok
                {:error, reason} ->
                  Logger.error("Failed to save translation for #{business_id}: #{inspect(reason)}")
                  {:error, reason}
              end

            {:error, reason} ->
              Logger.error("DeepL failed for #{business_id}: #{inspect(reason)}")
              {:error, reason}
          end
        end

      {:error, _} ->
        Logger.warning("Business not found: #{business_id}")
        {:error, :not_found}
    end
  end

  defp collect_translatable_fields(business) do
    fields = %{}
    fields = if non_empty?(business.description), do: Map.put(fields, :description, business.description), else: fields
    fields = if non_empty?(business.summary), do: Map.put(fields, :summary, business.summary), else: fields
    fields = if non_empty_list?(business.highlights), do: Map.put(fields, :highlights, business.highlights), else: fields
    fields = if non_empty_list?(business.warnings), do: Map.put(fields, :warnings, business.warnings), else: fields
    fields = if non_empty_list?(business.integration_tips), do: Map.put(fields, :integration_tips, business.integration_tips), else: fields
    fields = if non_empty_list?(business.cultural_notes), do: Map.put(fields, :cultural_notes, business.cultural_notes), else: fields
    fields
  end

  defp translate_fields(fields, locale) do
    alias GaliciaLocal.AI.DeepL

    {string_fields, array_fields} =
      Enum.split_with(fields, fn {_k, v} -> is_binary(v) end)

    string_keys = Enum.map(string_fields, fn {k, _v} -> k end)
    string_values = Enum.map(string_fields, fn {_k, v} -> v end)

    array_meta = Enum.map(array_fields, fn {k, list} -> {k, length(list)} end)
    array_values = Enum.flat_map(array_fields, fn {_k, list} -> list end)

    all_texts = string_values ++ array_values

    if Enum.empty?(all_texts) do
      {:ok, %{}}
    else
      case DeepL.translate_batch(all_texts, locale, source_lang: "en") do
        {:ok, translated_all} ->
          {translated_strings, translated_arrays_flat} =
            Enum.split(translated_all, length(string_values))

          string_result =
            Enum.zip(string_keys, translated_strings)
            |> Map.new()

          {array_result, _rest} =
            Enum.reduce(array_meta, {%{}, translated_arrays_flat}, fn {key, count}, {acc, remaining} ->
              {items, rest} = Enum.split(remaining, count)
              {Map.put(acc, key, items), rest}
            end)

          {:ok, Map.merge(string_result, array_result)}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp resolve_region_id(nil), do: nil

  defp resolve_region_id(slug) do
    import Ecto.Query

    case GaliciaLocal.Repo.one(
           from(r in "regions", where: r.slug == ^slug, select: r.id)
         ) do
      nil -> Mix.raise("Region not found: #{slug}")
      id -> Ecto.UUID.cast!(id)
    end
  end

  defp estimate_cost(count, type \\ :business) do
    # ~1000 chars per business, ~200 chars per city description
    chars_per_item = if type == :city, do: 200, else: 1000
    chars = count * chars_per_item
    cost = chars / 1_000_000 * 20

    Mix.shell().info(
      "Estimated DeepL cost: ~#{chars |> format_chars()} chars = ~$#{Float.round(cost, 2)}"
    )
  end

  defp format_chars(chars) when chars < 1000, do: "#{chars}"
  defp format_chars(chars) when chars < 1_000_000, do: "#{Float.round(chars / 1000, 1)}K"
  defp format_chars(chars), do: "#{Float.round(chars / 1_000_000, 1)}M"

  defp non_empty?(nil), do: false
  defp non_empty?(""), do: false
  defp non_empty?(_), do: true

  defp non_empty_list?(nil), do: false
  defp non_empty_list?([]), do: false
  defp non_empty_list?(_), do: true
end
