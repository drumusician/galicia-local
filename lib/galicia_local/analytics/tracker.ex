defmodule GaliciaLocal.Analytics.Tracker do
  @moduledoc """
  Lightweight page view tracker using SQL upsert.
  Tracks one row per page_type + resource_id + date, incrementing view_count.

  Usage in LiveViews:

      def mount(params, session, socket) do
        if connected?(socket) do
          Tracker.track_async("business", business.id)
        end
        ...
      end
  """

  alias GaliciaLocal.Repo

  @doc """
  Track a page view asynchronously (fire-and-forget).
  Only tracks on connected mounts to avoid double-counting.
  """
  def track_async(page_type, resource_id) do
    Task.start(fn -> track(page_type, resource_id) end)
  end

  @doc """
  Track a page view synchronously.
  """
  def track(page_type, resource_id) do
    today = Date.utc_today()

    Repo.query!(
      """
      INSERT INTO page_views (id, page_type, resource_id, date, view_count, inserted_at, updated_at)
      VALUES (gen_random_uuid(), $1, $2, $3, 1, now(), now())
      ON CONFLICT (page_type, resource_id, date)
      DO UPDATE SET view_count = page_views.view_count + 1, updated_at = now()
      """,
      [page_type, Ecto.UUID.dump!(resource_id), today]
    )
  end

  @doc """
  Get top viewed resources of a given type in the last N days.
  Returns [{resource_id, total_views}, ...]
  """
  def top(page_type, days \\ 30, limit \\ 20) do
    since = Date.add(Date.utc_today(), -days)

    %{rows: rows} =
      Repo.query!(
        """
        SELECT resource_id::text, SUM(view_count)::integer as total
        FROM page_views
        WHERE page_type = $1 AND date >= $2
        GROUP BY resource_id
        ORDER BY total DESC
        LIMIT $3
        """,
        [page_type, since, limit]
      )

    Enum.map(rows, fn [id, count] -> %{resource_id: id, views: count} end)
  end

  @doc """
  Get daily view counts for a specific resource over the last N days.
  """
  def daily(resource_id, days \\ 30) do
    since = Date.add(Date.utc_today(), -days)

    %{rows: rows} =
      Repo.query!(
        """
        SELECT date, view_count
        FROM page_views
        WHERE resource_id = $1 AND date >= $2
        ORDER BY date ASC
        """,
        [Ecto.UUID.dump!(resource_id), since]
      )

    Enum.map(rows, fn [date, count] -> %{date: date, views: count} end)
  end

  @doc """
  Get summary stats: total views by page_type in the last N days.
  """
  def summary(days \\ 30) do
    since = Date.add(Date.utc_today(), -days)

    %{rows: rows} =
      Repo.query!(
        """
        SELECT page_type, SUM(view_count)::integer as total, COUNT(DISTINCT resource_id)::integer as unique_resources
        FROM page_views
        WHERE date >= $1
        GROUP BY page_type
        ORDER BY total DESC
        """,
        [since]
      )

    Enum.map(rows, fn [type, total, unique] ->
      %{page_type: type, total_views: total, unique_resources: unique}
    end)
  end
end
