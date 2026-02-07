defmodule GaliciaLocal.Pipeline.PipelineStatus do
  @moduledoc """
  Queries for pipeline status: business counts by status, throughput,
  translation coverage, and Oban queue depths.
  """

  alias GaliciaLocal.Repo

  @doc """
  Get a full pipeline summary for a region (or all regions if nil).
  """
  def summary(region_id \\ nil) do
    %{
      funnel: business_funnel(region_id),
      throughput: throughput(region_id),
      translation_coverage: translation_coverage(region_id),
      queue_depths: queue_depths()
    }
  end

  @doc """
  Business counts by status - the pipeline funnel.
  """
  def business_funnel(region_id) do
    {region_clause, params} = region_filter(region_id)

    %{rows: rows} =
      Repo.query!(
        """
        SELECT status, COUNT(*)::integer
        FROM businesses
        WHERE 1=1 #{region_clause}
        GROUP BY status
        ORDER BY status
        """,
        params
      )

    counts = Map.new(rows, fn [status, count] -> {status, count} end)

    %{
      pending: counts["pending"] || 0,
      researching: counts["researching"] || 0,
      researched: counts["researched"] || 0,
      enriched: counts["enriched"] || 0,
      verified: counts["verified"] || 0,
      failed: counts["failed"] || 0,
      total: Enum.sum(Map.values(counts))
    }
  end

  @doc """
  Throughput: businesses enriched/translated in recent time periods.
  """
  def throughput(region_id) do
    {region_clause, base_params} = region_filter(region_id)
    now_param = "$#{length(base_params) + 1}"

    %{rows: [[enriched_24h]]} =
      Repo.query!(
        """
        SELECT COUNT(*)::integer
        FROM businesses
        WHERE last_enriched_at >= #{now_param}::timestamptz - interval '24 hours'
          #{region_clause}
        """,
        base_params ++ [DateTime.utc_now()]
      )

    %{rows: [[enriched_7d]]} =
      Repo.query!(
        """
        SELECT COUNT(*)::integer
        FROM businesses
        WHERE last_enriched_at >= #{now_param}::timestamptz - interval '7 days'
          #{region_clause}
        """,
        base_params ++ [DateTime.utc_now()]
      )

    %{rows: [[translated_24h]]} =
      Repo.query!(
        """
        SELECT COUNT(DISTINCT bt.business_id)::integer
        FROM business_translations bt
        JOIN businesses b ON b.id = bt.business_id
        WHERE bt.inserted_at >= #{now_param}::timestamptz - interval '24 hours'
          #{String.replace(region_clause, "AND ", "AND b.")}
        """,
        base_params ++ [DateTime.utc_now()]
      )

    %{
      enriched_24h: enriched_24h,
      enriched_7d: enriched_7d,
      translated_24h: translated_24h
    }
  end

  @doc """
  Translation coverage per locale.
  """
  def translation_coverage(region_id) do
    target_locales = GaliciaLocal.Directory.TranslationStatus.target_locales()
    {region_clause, base_params} = region_filter(region_id)

    %{rows: [[total_enriched]]} =
      Repo.query!(
        """
        SELECT COUNT(*)::integer FROM businesses
        WHERE status IN ('enriched', 'verified')
          AND description IS NOT NULL AND description != ''
          #{region_clause}
        """,
        base_params
      )

    locale_stats =
      for locale <- target_locales, into: %{} do
        locale_param = "$#{length(base_params) + 1}"

        %{rows: [[translated]]} =
          Repo.query!(
            """
            SELECT COUNT(*)::integer FROM businesses b
            WHERE b.status IN ('enriched', 'verified')
              AND b.description IS NOT NULL AND b.description != ''
              #{region_clause}
              AND EXISTS (
                SELECT 1 FROM business_translations bt
                WHERE bt.business_id = b.id AND bt.locale = #{locale_param}
                  AND bt.description IS NOT NULL AND bt.description != ''
              )
            """,
            base_params ++ [locale]
          )

        {locale, %{translated: translated, total: total_enriched}}
      end

    locale_stats
  end

  @doc """
  Current Oban queue depths.
  """
  def queue_depths do
    %{rows: rows} =
      Repo.query!("""
      SELECT queue, state, COUNT(*)::integer
      FROM oban_jobs
      WHERE state IN ('available', 'executing', 'scheduled', 'retryable')
      GROUP BY queue, state
      ORDER BY queue, state
      """)

    rows
    |> Enum.group_by(fn [queue, _state, _count] -> queue end)
    |> Enum.map(fn {queue, states} ->
      state_counts = Map.new(states, fn [_q, state, count] -> {state, count} end)

      {queue,
       %{
         available: state_counts["available"] || 0,
         executing: state_counts["executing"] || 0,
         scheduled: state_counts["scheduled"] || 0,
         retryable: state_counts["retryable"] || 0
       }}
    end)
    |> Map.new()
  end

  defp region_filter(nil), do: {"", []}

  defp region_filter(region_id) do
    {"AND region_id = $1", [Ecto.UUID.dump!(region_id)]}
  end
end
