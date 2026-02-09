defmodule GaliciaLocal.Workers.RegionDiscoveryScheduler do
  @moduledoc """
  Autonomous scheduler that discovers businesses for regions with underpopulated cities.

  Runs daily (configured via Oban Cron in worker.exs) and:
  1. Finds active regions with cities that have few or no businesses
  2. Queues OverpassImportWorker for cities needing discovery
  3. Queues BatchResearchWorker for regions with pending businesses

  This makes the content pipeline fully autonomous — add a region/city in admin,
  and the worker picks it up automatically.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 1,
    unique: [period: 3600]

  require Logger

  alias GaliciaLocal.Workers.OverpassImportWorker
  alias GaliciaLocal.Workers.BatchResearchWorker

  # Cities with fewer than this many total businesses get discovery queued
  @min_businesses_threshold 5

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("RegionDiscoveryScheduler: starting autonomous discovery check")

    regions = list_active_regions()
    Logger.info("RegionDiscoveryScheduler: found #{length(regions)} active regions")

    discovery_count = Enum.reduce(regions, 0, fn region, acc ->
      acc + process_region(region)
    end)

    # Also queue research for regions with pending businesses
    research_count = queue_research_for_pending(regions)

    Logger.info(
      "RegionDiscoveryScheduler: complete — " <>
      "#{discovery_count} discovery jobs queued, " <>
      "#{research_count} research batches queued"
    )

    :ok
  end

  defp list_active_regions do
    query = """
    SELECT id::text, name, slug
    FROM regions
    WHERE active = true
    ORDER BY name
    """

    %{rows: rows} = GaliciaLocal.Repo.query!(query)

    Enum.map(rows, fn [id, name, slug] ->
      %{id: id, name: name, slug: slug}
    end)
  end

  defp process_region(region) do
    cities = cities_needing_discovery(region.id)

    if cities == [] do
      Logger.info("RegionDiscoveryScheduler: #{region.name} — all cities have sufficient businesses")
      0
    else
      Logger.info(
        "RegionDiscoveryScheduler: #{region.name} — " <>
        "#{length(cities)} cities need discovery"
      )

      Enum.each(cities, fn {city_id, city_name, business_count} ->
        Logger.info("  → Queuing discovery for #{city_name} (#{business_count} businesses)")

        %{city_id: city_id, region_id: region.id}
        |> OverpassImportWorker.new()
        |> Oban.insert()
      end)

      length(cities)
    end
  end

  defp cities_needing_discovery(region_id) do
    query = """
    SELECT c.id::text, c.name, COUNT(b.id) as business_count
    FROM cities c
    LEFT JOIN businesses b ON b.city_id = c.id
    WHERE c.region_id = $1::uuid
    GROUP BY c.id, c.name
    HAVING COUNT(b.id) < $2
    ORDER BY COUNT(b.id) ASC, c.name
    """

    %{rows: rows} = GaliciaLocal.Repo.query!(query, [region_id, @min_businesses_threshold])

    Enum.map(rows, fn [id, name, count] -> {id, name, count} end)
  end

  defp queue_research_for_pending(regions) do
    Enum.reduce(regions, 0, fn region, acc ->
      pending = count_pending_with_websites(region.id)

      if pending > 0 do
        Logger.info(
          "RegionDiscoveryScheduler: #{region.name} has #{pending} pending businesses with websites — queuing research"
        )

        BatchResearchWorker.queue(region_id: region.id)
        acc + 1
      else
        acc
      end
    end)
  end

  defp count_pending_with_websites(region_id) do
    query = """
    SELECT COUNT(*)
    FROM businesses
    WHERE region_id = $1::uuid
      AND status = 'pending'
      AND website IS NOT NULL
      AND website != ''
    """

    %{rows: [[count]]} = GaliciaLocal.Repo.query!(query, [region_id])
    count
  end
end
