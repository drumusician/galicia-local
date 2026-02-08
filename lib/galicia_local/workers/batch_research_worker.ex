defmodule GaliciaLocal.Workers.BatchResearchWorker do
  @moduledoc """
  Oban worker that queues pending OSM businesses with websites through the research pipeline.

  Processes businesses in batches, staggering WebsiteCrawlWorker jobs to avoid
  overwhelming target websites and DuckDuckGo.

  ## Usage

      # Queue all pending OSM businesses with websites (all regions)
      GaliciaLocal.Workers.BatchResearchWorker.queue()

      # Queue for a specific region
      GaliciaLocal.Workers.BatchResearchWorker.queue(region_id: "uuid")

      # Queue with custom batch size
      GaliciaLocal.Workers.BatchResearchWorker.queue(batch_size: 50)
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 1,
    unique: [period: 300, fields: [:args, :queue, :worker]]

  require Logger

  alias GaliciaLocal.Scraper.Workers.WebsiteCrawlWorker

  @default_batch_size 100
  # Stagger jobs by 5 seconds each to be polite
  @stagger_seconds 5

  @doc """
  Queues the batch research worker.

  ## Options

    * `:region_id` - Only process businesses from this region
    * `:batch_size` - Number of businesses per batch (default: #{@default_batch_size})
    * `:offset` - Skip this many businesses (for resuming)
  """
  def queue(opts \\ []) do
    args =
      %{}
      |> maybe_put(:region_id, Keyword.get(opts, :region_id))
      |> maybe_put(:batch_size, Keyword.get(opts, :batch_size))
      |> maybe_put(:offset, Keyword.get(opts, :offset))

    args
    |> __MODULE__.new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    region_id = args["region_id"]
    batch_size = args["batch_size"] || @default_batch_size
    offset = args["offset"] || 0

    Logger.info("BatchResearch: Finding pending OSM businesses with websites (offset: #{offset}, batch: #{batch_size})")

    # Find pending OSM businesses that have websites
    region_filter = if region_id, do: "AND region_id = $3", else: ""

    params =
      if region_id,
        do: [batch_size, offset, region_id],
        else: [batch_size, offset]

    query = """
    SELECT id, name
    FROM businesses
    WHERE source = 'openstreetmap'
      AND status = 'pending'
      AND website IS NOT NULL
      AND website != ''
      #{region_filter}
    ORDER BY name
    LIMIT $1 OFFSET $2
    """

    %{rows: rows} = GaliciaLocal.Repo.query!(query, params)

    if rows == [] do
      Logger.info("BatchResearch: No more businesses to process. Done!")
      :ok
    else
      Logger.info("BatchResearch: Queuing #{length(rows)} businesses for research")

      # Queue WebsiteCrawlWorker for each business, staggered
      Enum.each(Enum.with_index(rows), fn {[id, name], idx} ->
        scheduled_at = DateTime.add(DateTime.utc_now(), idx * @stagger_seconds, :second)

        %{business_id: id}
        |> WebsiteCrawlWorker.new(scheduled_at: scheduled_at)
        |> Oban.insert()

        if rem(idx, 25) == 0 and idx > 0 do
          Logger.info("BatchResearch: Queued #{idx}/#{length(rows)} (latest: #{name})")
        end
      end)

      Logger.info("BatchResearch: Queued #{length(rows)} businesses, staggered over #{length(rows) * @stagger_seconds}s")

      # If we got a full batch, queue the next batch (after current batch finishes)
      if length(rows) == batch_size do
        next_offset = offset + batch_size
        next_delay = batch_size * @stagger_seconds

        next_args =
          %{"offset" => next_offset, "batch_size" => batch_size}
          |> maybe_put("region_id", region_id)

        next_args
        |> __MODULE__.new(scheduled_at: DateTime.add(DateTime.utc_now(), next_delay, :second))
        |> Oban.insert()

        Logger.info("BatchResearch: Next batch (offset #{next_offset}) scheduled in #{next_delay}s")
      end

      :ok
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  @doc """
  Returns the count of pending OSM businesses with websites, optionally by region.
  """
  def pending_count(opts \\ []) do
    region_id = Keyword.get(opts, :region_id)
    region_filter = if region_id, do: "AND region_id = $1", else: ""
    params = if region_id, do: [region_id], else: []

    query = """
    SELECT
      r.name,
      COUNT(*) as total
    FROM businesses b
    JOIN regions r ON b.region_id = r.id
    WHERE b.source = 'openstreetmap'
      AND b.status = 'pending'
      AND b.website IS NOT NULL
      AND b.website != ''
      #{region_filter}
    GROUP BY r.name
    ORDER BY total DESC
    """

    %{rows: rows} = GaliciaLocal.Repo.query!(query, params)
    rows
  end
end
