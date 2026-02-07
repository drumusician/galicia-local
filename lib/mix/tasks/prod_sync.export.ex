defmodule Mix.Tasks.ProdSync.Export do
  @shortdoc "Export local enrichment changes as SQL since last sync"
  @moduledoc """
  Reads the last sync timestamp and exports changed businesses and
  business_translations as SQL statements.

  Output goes to stdout so you can redirect to a file:

      mix prod_sync.export > tmp/prod_sync/changes.sql

  Options:

      --since TIMESTAMP   Override the timestamp (ISO 8601)
      --all               Export all enriched businesses, ignoring timestamp
  """

  use Mix.Task

  import Ecto.Query

  @timestamp_file "tmp/prod_sync/last_sync.txt"

  @business_fields [
    :description,
    :summary,
    :highlights,
    :warnings,
    :integration_tips,
    :cultural_notes,
    :service_specialties,
    :languages_spoken,
    :languages_taught,
    :speaks_english,
    :speaks_english_confidence,
    :newcomer_friendly_score,
    :local_gem_score,
    :quality_score,
    :category_fit_score,
    :suggested_category_slug,
    :sentiment_summary,
    :review_insights,
    :opening_hours,
    :status,
    :last_enriched_at,
    :updated_at
  ]

  @translation_fields [
    :business_id,
    :locale,
    :description,
    :summary,
    :highlights,
    :warnings,
    :integration_tips,
    :cultural_notes,
    :content_source,
    :source_locale
  ]

  @impl Mix.Task
  def run(argv) do
    {:ok, _} = Application.ensure_all_started(:postgrex)
    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    {:ok, _} = GaliciaLocal.Repo.start_link()

    {opts, _, _} =
      OptionParser.parse(argv, switches: [since: :string, all: :boolean])

    since = resolve_since(opts)

    businesses = fetch_businesses(since, opts[:all])
    translations = fetch_translations(since, opts[:all])

    Mix.shell().info("-- Prod sync export")
    Mix.shell().info("-- Generated: #{DateTime.utc_now() |> DateTime.to_iso8601()}")
    Mix.shell().info("-- Since: #{since || "all time"}")
    Mix.shell().info("-- Businesses: #{length(businesses)}")
    Mix.shell().info("-- Translations: #{length(translations)}")
    Mix.shell().info("")
    Mix.shell().info("BEGIN;")
    Mix.shell().info("")

    for business <- businesses do
      Mix.shell().info(business_update_sql(business))
    end

    if translations != [] do
      Mix.shell().info("")
    end

    for translation <- translations do
      Mix.shell().info(translation_upsert_sql(translation))
    end

    Mix.shell().info("")
    Mix.shell().info("COMMIT;")
  end

  defp resolve_since(opts) do
    cond do
      opts[:all] ->
        nil

      opts[:since] ->
        case DateTime.from_iso8601(opts[:since]) do
          {:ok, dt, _} -> dt
          _ -> Mix.raise("Invalid --since timestamp: #{opts[:since]}")
        end

      File.exists?(@timestamp_file) ->
        @timestamp_file
        |> File.read!()
        |> String.trim()
        |> DateTime.from_iso8601()
        |> case do
          {:ok, dt, _} -> dt
          _ -> Mix.raise("Invalid timestamp in #{@timestamp_file}")
        end

      true ->
        Mix.raise(
          "No timestamp file found at #{@timestamp_file}. " <>
            "Use --all to export everything, or run mix prod_sync.save_timestamp first."
        )
    end
  end

  @business_select_fields [:id | @business_fields]
  @translation_select_fields @translation_fields ++ [:updated_at]

  defp fetch_businesses(since, all?) do
    fields = @business_select_fields

    query =
      "businesses"
      |> where([b], not is_nil(b.summary))
      |> select([b], map(b, ^fields))

    query =
      if all? || is_nil(since) do
        query
      else
        where(query, [b], b.updated_at > ^since)
      end

    GaliciaLocal.Repo.all(query)
  end

  defp fetch_translations(since, all?) do
    fields = @translation_select_fields

    query =
      "business_translations"
      |> select([t], map(t, ^fields))

    query =
      if all? || is_nil(since) do
        query
      else
        where(query, [t], t.updated_at > ^since)
      end

    GaliciaLocal.Repo.all(query)
  end

  defp business_update_sql(business) do
    id = encode_uuid(business.id)

    sets =
      @business_fields
      |> Enum.map(fn field ->
        value = Map.get(business, field)
        "  #{field} = #{sql_value(field, value)}"
      end)
      |> Enum.join(",\n")

    "UPDATE businesses SET\n#{sets}\nWHERE id = #{sql_literal(id)};\n"
  end

  defp translation_upsert_sql(translation) do
    fields = @translation_fields
    columns = Enum.map_join(fields, ", ", &to_string/1)

    values =
      Enum.map_join(fields, ", ", fn field ->
        value = Map.get(translation, field)
        sql_value(field, value)
      end)

    update_fields = fields -- [:business_id, :locale]

    update_sets =
      Enum.map_join(update_fields, ", ", fn field ->
        "#{field} = EXCLUDED.#{field}"
      end)

    """
    INSERT INTO business_translations (#{columns})
    VALUES (#{values})
    ON CONFLICT (business_id, locale) DO UPDATE SET #{update_sets};
    """
  end

  defp sql_value(_field, nil), do: "NULL"
  defp sql_value(_field, true), do: "TRUE"
  defp sql_value(_field, false), do: "FALSE"

  defp sql_value(field, %DateTime{} = dt) when field in [:last_enriched_at, :updated_at] do
    sql_literal(DateTime.to_iso8601(dt))
  end

  defp sql_value(field, value) when field in [:id, :business_id] do
    sql_literal(encode_uuid(value))
  end

  defp sql_value(field, value)
       when field in [
              :speaks_english_confidence,
              :newcomer_friendly_score,
              :local_gem_score,
              :quality_score,
              :category_fit_score
            ] do
    if is_struct(value, Decimal), do: Decimal.to_string(value), else: to_string(value)
  end

  defp sql_value(field, value)
       when field in [
              :highlights,
              :warnings,
              :integration_tips,
              :cultural_notes,
              :service_specialties,
              :languages_spoken,
              :languages_taught
            ] do
    if is_list(value) and value != [] do
      elements = Enum.map_join(value, ", ", &sql_literal/1)
      "ARRAY[#{elements}]"
    else
      "ARRAY[]::text[]"
    end
  end

  defp sql_value(field, value) when field in [:review_insights, :opening_hours] do
    if is_map(value) and value != %{} do
      "#{sql_literal(Jason.encode!(value))}::jsonb"
    else
      "NULL"
    end
  end

  defp sql_value(:status, value) when is_atom(value), do: sql_literal(to_string(value))

  defp sql_value(:status, value) when is_binary(value), do: sql_literal(value)

  defp sql_value(_field, value) when is_binary(value), do: sql_literal(value)

  defp sql_value(_field, value), do: sql_literal(to_string(value))

  defp sql_literal(str) when is_binary(str) do
    escaped = String.replace(str, "'", "''")
    "'#{escaped}'"
  end

  defp encode_uuid(<<_::128>> = raw) do
    Ecto.UUID.load!(raw)
  end

  defp encode_uuid(str) when is_binary(str), do: str
end
