defmodule GaliciaLocal.Scraper.Pipelines.SaveToDatabase do
  @moduledoc """
  Crawly pipeline that saves scraped items to the database via Ash.
  """

  require Logger

  alias GaliciaLocal.Directory.Business

  @behaviour Crawly.Pipeline

  @impl Crawly.Pipeline
  def run(item, state) do
    case create_business(item) do
      {:ok, business} ->
        Logger.info("Saved business: #{business.name}")
        {item, state}

      {:error, error} ->
        Logger.warning("Failed to save business #{item[:name]}: #{inspect(error)}")
        # Return false to drop the item
        {false, state}
    end
  end

  defp create_business(item) do
    # Generate slug from name
    slug =
      (item[:name] || "unknown")
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9\s-]/, "")
      |> String.replace(~r/\s+/, "-")
      |> String.slice(0, 100)

    attrs = %{
      name: item[:name],
      slug: slug,
      address: item[:address],
      phone: item[:phone],
      website: item[:website],
      google_maps_url: item[:google_maps_url],
      latitude: item[:latitude],
      longitude: item[:longitude],
      rating: item[:rating],
      review_count: item[:review_count] || 0,
      price_level: item[:price_level],
      opening_hours: item[:opening_hours],
      status: :pending,
      source: item[:source] || :web_scrape,
      raw_data: %{
        place_id: item[:place_id],
        scraped_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        spider: item[:spider],
        reviews: item[:reviews]
      },
      city_id: item[:city_id],
      category_id: item[:category_id]
    }

    case Business.create(attrs) do
      {:ok, business} = result ->
        maybe_upsert_spanish_description(business, item[:description])
        result

      error ->
        error
    end
  end

  defp maybe_upsert_spanish_description(_business, nil), do: :ok
  defp maybe_upsert_spanish_description(_business, ""), do: :ok

  defp maybe_upsert_spanish_description(business, description) do
    alias GaliciaLocal.Directory.BusinessTranslation

    BusinessTranslation.upsert(%{
      business_id: business.id,
      locale: "es",
      description: description,
      content_source: "scraped",
      source_locale: "es"
    })
  end
end
