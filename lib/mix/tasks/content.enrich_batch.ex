defmodule Mix.Tasks.Content.EnrichBatch do
  @shortdoc "Batch-enrich unenriched businesses via Claude LLM"
  @moduledoc """
  Finds businesses that haven't been enriched yet and processes them through
  the Claude LLM enrichment pipeline in controlled batches.

  Targets businesses with status :pending or :researched that have reviews data
  but no summary yet. Each business costs ~1 Claude Sonnet API call (~$0.04).

  Usage:

      mix content.enrich_batch
      mix content.enrich_batch --limit 50
      mix content.enrich_batch --limit 20 --sleep 3
      mix content.enrich_batch --dry-run
      mix content.enrich_batch --region galicia --limit 100

  Options:

      --limit N         Max businesses to process (default: all)
      --sleep SECONDS   Delay between each business (default: 2)
      --dry-run         Show what would be enriched without making API calls
      --region REGION   Filter by region slug ("galicia" or "netherlands")
      --status STATUS   Filter by status: "pending", "researched", or "both" (default: "both")
  """

  use Mix.Task

  import Ecto.Query

  require Logger

  @impl Mix.Task
  def run(argv) do
    {:ok, _} = Application.ensure_all_started(:postgrex)
    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    {:ok, _} = GaliciaLocal.Repo.start_link()

    {opts, _, _} =
      OptionParser.parse(argv,
        switches: [limit: :integer, sleep: :integer, dry_run: :boolean, region: :string, status: :string]
      )

    limit = opts[:limit]
    sleep_seconds = opts[:sleep] || 2
    dry_run? = opts[:dry_run] || false
    region_slug = opts[:region]
    status_filter = opts[:status] || "both"

    region_id = resolve_region_id(region_slug)
    business_ids = find_unenriched(region_id, status_filter)

    business_ids =
      if limit do
        Enum.take(business_ids, limit)
      else
        business_ids
      end

    total = length(business_ids)

    Mix.shell().info("Found #{total} businesses needing enrichment")

    if dry_run? do
      Mix.shell().info("[DRY RUN] Would enrich #{total} businesses via Claude LLM")
      estimate_cost(total)

      business_ids
      |> Enum.take(10)
      |> load_and_display()

      if total > 10 do
        Mix.shell().info("  ... and #{total - 10} more")
      end
    else
      if total == 0 do
        Mix.shell().info("Nothing to enrich!")
      else
        estimate_cost(total)
        Mix.shell().info("Starting enrichment (#{sleep_seconds}s delay between each)...")
        Mix.shell().info("")

        results = process_enrichments(business_ids, sleep_seconds)

        successes = Enum.count(results, fn {_, status} -> status == :ok end)
        failures = Enum.count(results, fn {_, status} -> status != :ok end)

        Mix.shell().info("")
        Mix.shell().info("Done! #{successes} enriched, #{failures} failed out of #{total}")

        if failures > 0 do
          failed_ids = results |> Enum.filter(fn {_, s} -> s != :ok end) |> Enum.map(fn {id, _} -> id end)
          Mix.shell().info("Failed IDs: #{Enum.join(failed_ids, ", ")}")
        end
      end
    end
  end

  defp find_unenriched(region_id, status_filter) do
    statuses =
      case status_filter do
        "pending" -> ["pending"]
        "researched" -> ["researched"]
        "researching" -> ["researching"]
        _ -> ["pending", "researching", "researched"]
      end

    region_clause =
      if region_id do
        "AND b.region_id = '#{region_id}'"
      else
        ""
      end

    status_list = Enum.map_join(statuses, ", ", &"'#{&1}'")

    %{rows: rows} =
      GaliciaLocal.Repo.query!("""
      SELECT b.id::text, b.name, b.status::text,
             CASE WHEN b.raw_data->>'reviews_text' IS NOT NULL THEN true ELSE false END as has_reviews
      FROM businesses b
      WHERE b.status IN (#{status_list})
        AND b.summary IS NULL
        #{region_clause}
      ORDER BY
        CASE WHEN b.raw_data->>'reviews_text' IS NOT NULL THEN 0 ELSE 1 END,
        b.rating DESC NULLS LAST
      """)

    Enum.map(rows, fn [id | _] -> id end)
  end

  defp load_and_display(ids) do
    Enum.each(ids, fn id ->
      %{rows: rows} =
        GaliciaLocal.Repo.query!("""
        SELECT b.name, b.status::text, b.rating,
               (b.raw_data->>'reviews_text' IS NOT NULL) as has_reviews
        FROM businesses b WHERE b.id = $1::uuid
        """, [id])

      case rows do
        [[name, status, rating, has_reviews]] ->
          reviews_tag = if has_reviews, do: " [has reviews]", else: ""
          rating_str = if rating, do: " (#{rating}*)", else: ""
          Mix.shell().info("  #{name}#{rating_str} — #{status}#{reviews_tag}")

        _ ->
          Mix.shell().info("  #{id} — not found")
      end
    end)
  end

  defp process_enrichments(ids, sleep_seconds) do
    total = length(ids)

    ids
    |> Enum.with_index(1)
    |> Enum.map(fn {id, index} ->
      if index > 1 do
        Process.sleep(sleep_seconds * 1000)
      end

      result = enrich_one(id)

      status_str =
        case result do
          :ok -> "OK"
          {:error, reason} -> "FAIL: #{inspect(reason)}"
        end

      # Load name for display
      name =
        case GaliciaLocal.Repo.query!("SELECT name FROM businesses WHERE id = $1::uuid", [id]) do
          %{rows: [[n]]} -> n
          _ -> id
        end

      Mix.shell().info("  [#{index}/#{total}] #{name} — #{status_str}")

      {id, result}
    end)
  end

  defp enrich_one(business_id) do
    alias GaliciaLocal.Directory.Business

    case Business.get_by_id(business_id) do
      {:ok, business} ->
        case Business.enrich_with_llm(business) do
          {:ok, _enriched} -> :ok
          {:error, reason} ->
            Logger.error("Enrichment failed for #{business_id}: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, _} ->
        {:error, :not_found}
    end
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

  defp estimate_cost(count) do
    # ~$0.04 per business for Claude Sonnet enrichment
    cost = count * 0.04

    Mix.shell().info(
      "Estimated Claude API cost: #{count} businesses x ~$0.04 = ~$#{Float.round(cost, 2)}"
    )
  end
end
