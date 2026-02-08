defmodule GaliciaLocal.Directory.Business.Quality do
  @moduledoc """
  Calculates a data completeness score for a business listing.
  Used in admin UI to identify sparse listings that need enrichment.
  """

  @doc """
  Calculate data completeness as a percentage (0-100).
  """
  def score(business) do
    checks = [
      {has_value?(business.description), 15},
      {has_value?(business.summary), 10},
      {has_value?(business.phone), 5},
      {has_value?(business.website), 5},
      {has_value?(business.address), 5},
      {has_photos?(business), 20},
      {has_opening_hours?(business), 10},
      {has_rating?(business), 10},
      {has_reviews?(business), 10},
      {has_highlights?(business), 5},
      {has_location?(business), 5}
    ]

    Enum.reduce(checks, 0, fn
      {true, weight}, acc -> acc + weight
      {false, _}, acc -> acc
    end)
  end

  @doc """
  Returns a list of {label, present?} tuples for display in the UI.
  """
  def checklist(business) do
    [
      {"Photos", has_photos?(business)},
      {"Hours", has_opening_hours?(business)},
      {"Rating", has_rating?(business)},
      {"Reviews", has_reviews?(business)},
      {"Phone", has_value?(business.phone)},
      {"Website", has_value?(business.website)},
      {"Description", has_value?(business.description)},
      {"Summary", has_value?(business.summary)}
    ]
  end

  defp has_value?(nil), do: false
  defp has_value?(""), do: false
  defp has_value?(_), do: true

  defp has_photos?(%{photo_urls: urls}) when is_list(urls) and urls != [], do: true
  defp has_photos?(_), do: false

  defp has_opening_hours?(%{opening_hours: hours}) when is_map(hours) and map_size(hours) > 0,
    do: true

  defp has_opening_hours?(_), do: false

  defp has_rating?(%{rating: rating}) when not is_nil(rating), do: true
  defp has_rating?(_), do: false

  defp has_reviews?(%{raw_data: %{"reviews" => [_ | _]}}), do: true
  defp has_reviews?(_), do: false

  defp has_highlights?(%{highlights: [_ | _]}), do: true
  defp has_highlights?(_), do: false

  defp has_location?(%{latitude: lat, longitude: lng})
       when not is_nil(lat) and not is_nil(lng),
       do: true

  defp has_location?(_), do: false
end
