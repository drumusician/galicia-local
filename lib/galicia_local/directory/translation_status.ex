defmodule GaliciaLocal.Directory.TranslationStatus do
  @moduledoc """
  Queries to compute translation completeness across entities.
  Used by the admin translations page to show what needs translating.
  """

  alias GaliciaLocal.Repo

  @target_locales ["es", "nl"]

  def target_locales, do: @target_locales

  @doc """
  Get translation status for all entity types.
  Returns a map with completeness counts per entity type and locale.

  Options:
    - `:region_id` - filter businesses and cities by region (required for accurate counts)
  """
  def summary(opts \\ []) do
    region_id = Keyword.get(opts, :region_id)

    %{
      businesses: business_status(region_id),
      categories: category_status(),
      cities: city_status(region_id)
    }
  end

  @doc """
  Get IDs of entities missing translations for a given locale.
  Used to queue translation jobs.
  """
  def missing_business_ids(locale, region_id) do
    {region_clause, params} =
      if region_id do
        {"AND b.region_id = $2", [locale, Ecto.UUID.dump!(region_id)]}
      else
        {"", [locale]}
      end

    %{rows: rows} =
      Repo.query!("""
      SELECT b.id::text
      FROM businesses b
      WHERE b.status IN ('enriched', 'verified')
        AND b.description IS NOT NULL AND b.description != ''
        #{region_clause}
        AND NOT EXISTS (
          SELECT 1 FROM business_translations bt
          WHERE bt.business_id = b.id AND bt.locale = $1
            AND bt.description IS NOT NULL AND bt.description != ''
        )
      ORDER BY b.inserted_at DESC
      """, params)

    Enum.map(rows, fn [id] -> id end)
  end

  def missing_category_ids(locale) do
    %{rows: rows} =
      Repo.query!("""
      SELECT c.id::text
      FROM categories c
      WHERE c.name IS NOT NULL AND c.name != ''
        AND NOT EXISTS (
          SELECT 1 FROM category_translations ct
          WHERE ct.category_id = c.id AND ct.locale = $1
            AND ct.name IS NOT NULL AND ct.name != ''
        )
      """, [locale])

    Enum.map(rows, fn [id] -> id end)
  end

  def missing_city_ids(locale, region_id) do
    {region_clause, params} =
      if region_id do
        {"AND c.region_id = $2", [locale, Ecto.UUID.dump!(region_id)]}
      else
        {"", [locale]}
      end

    %{rows: rows} =
      Repo.query!("""
      SELECT c.id::text
      FROM cities c
      WHERE c.description IS NOT NULL AND c.description != ''
        #{region_clause}
        AND NOT EXISTS (
          SELECT 1 FROM city_translations ct
          WHERE ct.city_id = c.id AND ct.locale = $1
            AND ct.description IS NOT NULL AND ct.description != ''
        )
      """, params)

    Enum.map(rows, fn [id] -> id end)
  end

  defp business_status(region_id) do
    {region_clause, base_params} =
      if region_id do
        {"AND b.region_id = $1", [Ecto.UUID.dump!(region_id)]}
      else
        {"", []}
      end

    %{rows: [[total]]} =
      Repo.query!("""
      SELECT COUNT(*)::integer
      FROM businesses b
      WHERE b.status IN ('enriched', 'verified')
        AND b.description IS NOT NULL AND b.description != ''
        #{region_clause}
      """, base_params)

    locale_counts =
      for locale <- @target_locales, into: %{} do
        params =
          if region_id do
            [Ecto.UUID.dump!(region_id), locale]
          else
            [locale]
          end

        locale_param = if region_id, do: "$2", else: "$1"

        %{rows: [[count]]} =
          Repo.query!("""
          SELECT COUNT(*)::integer
          FROM businesses b
          WHERE b.status IN ('enriched', 'verified')
            AND b.description IS NOT NULL AND b.description != ''
            #{region_clause}
            AND EXISTS (
              SELECT 1 FROM business_translations bt
              WHERE bt.business_id = b.id AND bt.locale = #{locale_param}
                AND bt.description IS NOT NULL AND bt.description != ''
            )
          """, params)

        {locale, count}
      end

    Map.put(locale_counts, :total, total)
  end

  defp category_status do
    %{rows: [[total]]} =
      Repo.query!("SELECT COUNT(*)::integer FROM categories WHERE name IS NOT NULL AND name != ''")

    locale_counts =
      for locale <- @target_locales, into: %{} do
        %{rows: [[count]]} =
          Repo.query!("""
          SELECT COUNT(*)::integer
          FROM categories c
          WHERE c.name IS NOT NULL AND c.name != ''
            AND EXISTS (
              SELECT 1 FROM category_translations ct
              WHERE ct.category_id = c.id AND ct.locale = $1
                AND ct.name IS NOT NULL AND ct.name != ''
            )
          """, [locale])

        {locale, count}
      end

    Map.put(locale_counts, :total, total)
  end

  defp city_status(region_id) do
    {region_clause, base_params} =
      if region_id do
        {"AND c.region_id = $1", [Ecto.UUID.dump!(region_id)]}
      else
        {"", []}
      end

    %{rows: [[total]]} =
      Repo.query!("""
      SELECT COUNT(*)::integer
      FROM cities c
      WHERE c.description IS NOT NULL AND c.description != ''
        #{region_clause}
      """, base_params)

    locale_counts =
      for locale <- @target_locales, into: %{} do
        params =
          if region_id do
            [Ecto.UUID.dump!(region_id), locale]
          else
            [locale]
          end

        locale_param = if region_id, do: "$2", else: "$1"

        %{rows: [[count]]} =
          Repo.query!("""
          SELECT COUNT(*)::integer
          FROM cities c
          WHERE c.description IS NOT NULL AND c.description != ''
            #{region_clause}
            AND EXISTS (
              SELECT 1 FROM city_translations ct
              WHERE ct.city_id = c.id AND ct.locale = #{locale_param}
                AND ct.description IS NOT NULL AND ct.description != ''
            )
          """, params)

        {locale, count}
      end

    Map.put(locale_counts, :total, total)
  end
end
