defmodule GaliciaLocal.Analytics.Tracker do
  @moduledoc """
  Lightweight page view tracker using SQL upsert.
  Tracks one row per page_type + resource_id + region_id + date, incrementing view_count.

  Usage in LiveViews:

      def mount(params, session, socket) do
        if connected?(socket) do
          Tracker.track_async("business", business.id, region.id)
        end
        ...
      end
  """

  alias GaliciaLocal.Repo

  @doc """
  Track a page view asynchronously (fire-and-forget).
  Only tracks on connected mounts to avoid double-counting.
  """
  def track_async(page_type, resource_id, region_id) do
    Task.start(fn -> track(page_type, resource_id, region_id) end)
  end

  @doc """
  Track a page view synchronously.
  """
  def track(page_type, resource_id, region_id) do
    today = Date.utc_today()

    Repo.query!(
      """
      INSERT INTO page_views (id, page_type, resource_id, region_id, date, view_count, inserted_at, updated_at)
      VALUES (gen_random_uuid(), $1, $2, $3, $4, 1, now(), now())
      ON CONFLICT (page_type, resource_id, date, region_id)
      DO UPDATE SET view_count = page_views.view_count + 1, updated_at = now()
      """,
      [page_type, Ecto.UUID.dump!(resource_id), Ecto.UUID.dump!(region_id), today]
    )
  end

  @doc """
  Get top viewed resources of a given type.

  Options:
    - `:days` - number of days to look back (default: 30)
    - `:limit` - max results (default: 20)
    - `:region_id` - filter by region (default: nil, shows all)
  """
  def top(page_type, opts \\ []) do
    days = Keyword.get(opts, :days, 30)
    limit = Keyword.get(opts, :limit, 20)
    region_id = Keyword.get(opts, :region_id)
    since = Date.add(Date.utc_today(), -days)

    {region_clause, params} =
      if region_id do
        {"AND region_id = $4", [page_type, since, limit, Ecto.UUID.dump!(region_id)]}
      else
        {"", [page_type, since, limit]}
      end

    %{rows: rows} =
      Repo.query!(
        """
        SELECT resource_id::text, SUM(view_count)::integer as total
        FROM page_views
        WHERE page_type = $1 AND date >= $2 #{region_clause}
        GROUP BY resource_id
        ORDER BY total DESC
        LIMIT $3
        """,
        params
      )

    Enum.map(rows, fn [id, count] -> %{resource_id: id, views: count} end)
  end

  @doc """
  Get daily view counts for a specific resource.

  Options:
    - `:days` - number of days to look back (default: 30)
    - `:region_id` - filter by region (default: nil, shows all)
  """
  def daily(resource_id, opts \\ []) do
    days = Keyword.get(opts, :days, 30)
    region_id = Keyword.get(opts, :region_id)
    since = Date.add(Date.utc_today(), -days)

    {region_clause, params} =
      if region_id do
        {"AND region_id = $3", [Ecto.UUID.dump!(resource_id), since, Ecto.UUID.dump!(region_id)]}
      else
        {"", [Ecto.UUID.dump!(resource_id), since]}
      end

    %{rows: rows} =
      Repo.query!(
        """
        SELECT date, view_count
        FROM page_views
        WHERE resource_id = $1 AND date >= $2 #{region_clause}
        ORDER BY date ASC
        """,
        params
      )

    Enum.map(rows, fn [date, count] -> %{date: date, views: count} end)
  end

  @doc """
  Get summary stats: total views by page_type.

  Options:
    - `:days` - number of days to look back (default: 30)
    - `:region_id` - filter by region (default: nil, shows all)
  """
  def summary(opts \\ []) do
    days = Keyword.get(opts, :days, 30)
    region_id = Keyword.get(opts, :region_id)
    since = Date.add(Date.utc_today(), -days)

    {region_clause, params} =
      if region_id do
        {"AND region_id = $2", [since, Ecto.UUID.dump!(region_id)]}
      else
        {"", [since]}
      end

    %{rows: rows} =
      Repo.query!(
        """
        SELECT page_type, SUM(view_count)::integer as total, COUNT(DISTINCT resource_id)::integer as unique_resources
        FROM page_views
        WHERE date >= $1 #{region_clause}
        GROUP BY page_type
        ORDER BY total DESC
        """,
        params
      )

    Enum.map(rows, fn [type, total, unique] ->
      %{page_type: type, total_views: total, unique_resources: unique}
    end)
  end
end
