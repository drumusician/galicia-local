defmodule GaliciaLocal.Directory.Business.Changes.EnrichWithGooglePlaces do
  @moduledoc """
  Ash change that enriches a business with data from Google Places API.

  Fetches place details (photos, opening hours, rating, reviews) and merges
  them into the business record. Stores reviews in raw_data for later LLM use.

  This is a data-fetching step. After running this, the admin should trigger
  LLM re-enrichment to generate highlights/description from the new reviews.
  """
  use Ash.Resource.Change

  require Logger

  alias GaliciaLocal.Scraper.GooglePlaces

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      place_id = Ash.Changeset.get_argument(changeset, :google_place_id)

      case GooglePlaces.get_place_details(place_id) do
        {:ok, details} ->
          attrs = build_attrs(details, changeset.data)

          changeset
          |> Ash.Changeset.force_change_attributes(attrs)
          |> Ash.Changeset.force_change_attribute(:last_enriched_at, DateTime.utc_now())

        {:error, reason} ->
          Logger.error("Google Places enrichment failed for #{changeset.data.id}: #{inspect(reason)}")

          Ash.Changeset.add_error(changeset,
            field: :base,
            message: "Google Places lookup failed: #{inspect(reason)}"
          )
      end
    end)
  end

  defp build_attrs(details, business) do
    existing_raw = business.raw_data || %{}

    merged_raw =
      Map.merge(existing_raw, %{
        "google_place_id" => details[:place_id],
        "google_types" => details[:types],
        "reviews" => Enum.map(details[:reviews] || [], &stringify_keys/1),
        "editorial_summary" => details[:editorial_summary],
        "google_enriched_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      })

    %{
      raw_data: merged_raw,
      source: :google_maps,
      photo_urls: details[:photos] || business.photo_urls || [],
      opening_hours: details[:opening_hours] || business.opening_hours,
      rating: details[:rating] || business.rating,
      review_count: details[:review_count] || business.review_count,
      google_maps_url: details[:google_maps_url] || business.google_maps_url
    }
    |> maybe_fill(:phone, details[:phone], business.phone)
    |> maybe_fill(:website, details[:website], business.website)
    |> maybe_fill(:price_level, details[:price_level], business.price_level)
  end

  # Only set a field if the business doesn't already have a value
  defp maybe_fill(attrs, key, new_value, current_value) do
    if is_nil(current_value) and not is_nil(new_value) do
      Map.put(attrs, key, new_value)
    else
      attrs
    end
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), stringify_keys(v)}
      {k, v} -> {k, stringify_keys(v)}
    end)
  end

  defp stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)
  defp stringify_keys(value), do: value
end
