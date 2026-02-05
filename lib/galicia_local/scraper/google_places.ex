defmodule GaliciaLocal.Scraper.GooglePlaces do
  @moduledoc """
  Google Places API client for scraping business listings.

  Uses the Places API (New) for text search and place details.
  Set GOOGLE_PLACES_API_KEY in your environment.
  """

  require Logger

  alias GaliciaLocal.Scraper.ApiCache

  @base_url "https://places.googleapis.com/v1"

  @doc """
  Search for businesses in a specific location.

  ## Options
    - :location - {lat, lng} tuple for the search center (used with locationBias)
    - :radius - Search radius in meters (default: 10000, used with locationBias)
    - :bounds - {south, west, north, east} tuple for strict bounding box (uses locationRestriction)
    - :language - Language code (default: "es")
    - :max_results - Maximum results to return (default: 20, max: 20 per request)

  When :bounds is provided, it takes precedence over :location/:radius and uses
  Google's locationRestriction (strict) instead of locationBias (preference).

  ## Examples
      # Circle-based search (locationBias)
      GooglePlaces.search("lawyers", location: {42.3396, -7.8642}, radius: 5000)

      # Rectangle-based search (locationRestriction)
      GooglePlaces.search("lawyers", bounds: {42.0, -9.0, 43.5, -7.0})
  """
  def search(query, opts \\ []) do
    case api_key() do
      nil ->
        Logger.warning("GOOGLE_PLACES_API_KEY not set, using mock data")
        {:ok, mock_search_results(query, opts)}

      key ->
        ApiCache.get_or_fetch({:search, query, opts}, fn -> do_search(query, key, opts) end)
    end
  end

  @doc """
  Get detailed information about a specific place.
  """
  def get_place_details(place_id) do
    case api_key() do
      nil ->
        Logger.warning("GOOGLE_PLACES_API_KEY not set")
        {:error, :no_api_key}

      key ->
        ApiCache.get_or_fetch({:details, place_id}, fn -> do_get_place_details(place_id, key) end)
    end
  end

  @doc """
  Search and get full details for all results.
  Returns a list of fully enriched place data.
  """
  def search_with_details(query, opts \\ []) do
    with {:ok, places} <- search(query, opts) do
      enriched =
        places
        |> Task.async_stream(
          fn place ->
            case get_place_details(place["place_id"] || place[:place_id]) do
              {:ok, details} -> Map.merge(place, details)
              {:error, _} -> place
            end
          end,
          max_concurrency: 5,
          timeout: 30_000
        )
        |> Enum.map(fn
          {:ok, result} -> result
          {:exit, _} -> nil
        end)
        |> Enum.reject(&is_nil/1)

      {:ok, enriched}
    end
  end

  # Private implementation

  defp do_search(query, api_key, opts) do
    location = Keyword.get(opts, :location)
    radius = Keyword.get(opts, :radius, 10_000)
    bounds = Keyword.get(opts, :bounds)
    language = Keyword.get(opts, :language, "es")

    body =
      %{
        textQuery: query,
        languageCode: language,
        maxResultCount: 20
      }
      |> maybe_add_location_restriction(bounds)
      |> maybe_add_location_bias(location, radius)

    # Fields to request - comprehensive list
    field_mask = [
      "places.id",
      "places.displayName",
      "places.formattedAddress",
      "places.location",
      "places.rating",
      "places.userRatingCount",
      "places.priceLevel",
      "places.websiteUri",
      "places.internationalPhoneNumber",
      "places.nationalPhoneNumber",
      "places.googleMapsUri",
      "places.businessStatus",
      "places.types",
      "places.currentOpeningHours",
      "places.regularOpeningHours"
    ]

    headers = [
      {"Content-Type", "application/json"},
      {"X-Goog-Api-Key", api_key},
      {"X-Goog-FieldMask", Enum.join(field_mask, ",")}
    ]

    url = "#{@base_url}/places:searchText"

    case Req.post(url, json: body, headers: headers) do
      {:ok, %{status: 200, body: %{"places" => places}}} ->
        {:ok, Enum.map(places, &normalize_place/1)}

      {:ok, %{status: 200, body: _empty}} ->
        {:ok, []}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Google Places API error: #{status} - #{inspect(body)}")
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        Logger.error("Google Places API request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp do_get_place_details(place_id, api_key) do
    field_mask = [
      "id",
      "displayName",
      "formattedAddress",
      "location",
      "rating",
      "userRatingCount",
      "priceLevel",
      "websiteUri",
      "internationalPhoneNumber",
      "nationalPhoneNumber",
      "googleMapsUri",
      "businessStatus",
      "types",
      "currentOpeningHours",
      "regularOpeningHours",
      "reviews",
      "editorialSummary",
      "photos"
    ]

    headers = [
      {"X-Goog-Api-Key", api_key},
      {"X-Goog-FieldMask", Enum.join(field_mask, ",")}
    ]

    url = "#{@base_url}/places/#{place_id}"

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, normalize_place(body)}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Google Places details error: #{status}")
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # locationRestriction takes precedence - if bounds are set, don't add locationBias
  defp maybe_add_location_bias(body, _location, _radius) when is_map_key(body, :locationRestriction), do: body
  defp maybe_add_location_bias(body, nil, _radius), do: body

  defp maybe_add_location_bias(body, {lat, lng}, radius) do
    Map.put(body, :locationBias, %{
      circle: %{
        center: %{latitude: lat, longitude: lng},
        radius: radius
      }
    })
  end

  defp maybe_add_location_restriction(body, nil), do: body

  defp maybe_add_location_restriction(body, {south, west, north, east}) do
    Map.put(body, :locationRestriction, %{
      rectangle: %{
        low: %{latitude: south, longitude: west},
        high: %{latitude: north, longitude: east}
      }
    })
  end

  @doc """
  Build a photo URL from a Google Places photo resource name.
  Uses the Places API (New) photo endpoint.
  """
  def photo_url(photo_name, max_width \\ 800) do
    case api_key() do
      nil -> nil
      key -> "#{@base_url}/#{photo_name}/media?maxWidthPx=#{max_width}&key=#{key}"
    end
  end

  defp normalize_place(place) do
    %{
      place_id: place["id"],
      name: get_in(place, ["displayName", "text"]),
      address: place["formattedAddress"],
      latitude: get_in(place, ["location", "latitude"]),
      longitude: get_in(place, ["location", "longitude"]),
      rating: place["rating"],
      review_count: place["userRatingCount"],
      price_level: normalize_price_level(place["priceLevel"]),
      website: place["websiteUri"],
      phone: place["internationalPhoneNumber"] || place["nationalPhoneNumber"],
      google_maps_url: place["googleMapsUri"],
      business_status: place["businessStatus"],
      types: place["types"] || [],
      opening_hours: normalize_opening_hours(place["regularOpeningHours"]),
      reviews: normalize_reviews(place["reviews"]),
      photos: normalize_photos(place["photos"]),
      editorial_summary: get_in(place, ["editorialSummary", "text"]),
      raw_data: place
    }
  end

  defp normalize_price_level(nil), do: nil
  defp normalize_price_level("PRICE_LEVEL_FREE"), do: 1
  defp normalize_price_level("PRICE_LEVEL_INEXPENSIVE"), do: 1
  defp normalize_price_level("PRICE_LEVEL_MODERATE"), do: 2
  defp normalize_price_level("PRICE_LEVEL_EXPENSIVE"), do: 3
  defp normalize_price_level("PRICE_LEVEL_VERY_EXPENSIVE"), do: 4
  defp normalize_price_level(_), do: nil

  defp normalize_opening_hours(nil), do: nil

  defp normalize_opening_hours(%{"weekdayDescriptions" => descriptions}) do
    descriptions
    |> Enum.with_index()
    |> Map.new(fn {desc, idx} ->
      day =
        case idx do
          0 -> "monday"
          1 -> "tuesday"
          2 -> "wednesday"
          3 -> "thursday"
          4 -> "friday"
          5 -> "saturday"
          6 -> "sunday"
        end

      {day, desc}
    end)
  end

  defp normalize_opening_hours(_), do: nil

  defp normalize_reviews(nil), do: []

  defp normalize_reviews(reviews) when is_list(reviews) do
    Enum.map(reviews, fn review ->
      %{
        author: get_in(review, ["authorAttribution", "displayName"]),
        rating: review["rating"],
        text: get_in(review, ["text", "text"]),
        language: get_in(review, ["text", "languageCode"]),
        time: review["publishTime"]
      }
    end)
  end

  defp normalize_reviews(_), do: []

  defp normalize_photos(nil), do: []

  defp normalize_photos(photos) when is_list(photos) do
    photos
    |> Enum.take(5)
    |> Enum.map(fn photo ->
      photo_name = photo["name"]
      if photo_name, do: photo_url(photo_name), else: nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_photos(_), do: []

  defp api_key do
    System.get_env("GOOGLE_PLACES_API_KEY")
  end

  @doc """
  Look up a city by name in a region. Returns basic location info.
  Accepts optional region parameter with name and country_code.
  """
  def lookup_city(city_name, opts \\ []) do
    region_name = Keyword.get(opts, :region_name, "Galicia")
    country = Keyword.get(opts, :country, "Spain")

    case api_key() do
      nil ->
        Logger.warning("GOOGLE_PLACES_API_KEY not set, using mock city data")
        {:ok, mock_city_result(city_name, region_name, country)}

      key ->
        cache_key = {:city_lookup, city_name, region_name, country}
        ApiCache.get_or_fetch(cache_key, fn -> do_lookup_city(city_name, region_name, country, key) end)
    end
  end

  defp do_lookup_city(city_name, region_name, country, api_key) do
    # Build location string - if region is the country (e.g., Netherlands), don't repeat
    location = if region_name == country, do: country, else: "#{region_name}, #{country}"

    body = %{
      textQuery: "#{city_name}, #{location}",
      languageCode: "en",
      maxResultCount: 5
    }

    field_mask = [
      "places.id",
      "places.displayName",
      "places.formattedAddress",
      "places.location",
      "places.photos",
      "places.editorialSummary"
    ]

    headers = [
      {"Content-Type", "application/json"},
      {"X-Goog-Api-Key", api_key},
      {"X-Goog-FieldMask", Enum.join(field_mask, ",")}
    ]

    url = "#{@base_url}/places:searchText"

    case Req.post(url, json: body, headers: headers) do
      {:ok, %{status: 200, body: %{"places" => places}}} ->
        results =
          places
          |> Enum.map(fn place ->
            photos = normalize_photos(place["photos"])

            %{
              name: get_in(place, ["displayName", "text"]),
              address: place["formattedAddress"],
              latitude: get_in(place, ["location", "latitude"]),
              longitude: get_in(place, ["location", "longitude"]),
              editorial_summary: get_in(place, ["editorialSummary", "text"]),
              image_url: List.first(photos)
            }
          end)

        {:ok, results}

      {:ok, %{status: 200, body: _empty}} ->
        {:ok, []}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Google Places city lookup error: #{status} - #{inspect(body)}")
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        Logger.error("Google Places city lookup failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp mock_city_result(city_name, region_name, country) do
    location = if region_name == country, do: country, else: "#{region_name}, #{country}"

    # Default coordinates based on region
    {base_lat, base_lng} = case region_name do
      "Netherlands" -> {52.37, 4.89}  # Amsterdam area
      "Galicia" -> {42.34, -8.5}       # Galicia area
      _ -> {42.34, -8.5}
    end

    [
      %{
        name: city_name,
        address: "#{city_name}, #{location}",
        latitude: base_lat + :rand.uniform() * 0.5,
        longitude: base_lng + :rand.uniform() * 0.5,
        editorial_summary: "A charming city in #{region_name}.",
        image_url: nil
      }
    ]
  end

  # Mock data for development without API key
  defp mock_search_results(query, opts) do
    location = Keyword.get(opts, :location, {42.3396, -7.8642})
    {base_lat, base_lng} = location

    query_lower = String.downcase(query)

    businesses =
      cond do
        String.contains?(query_lower, "lawyer") or String.contains?(query_lower, "abogado") ->
          [
            %{
              place_id: "mock_lawyer_1",
              name: "Bufete Rodríguez & Asociados",
              address: "Calle Real 45, Ourense",
              latitude: base_lat + 0.002,
              longitude: base_lng + 0.001,
              rating: 4.7,
              review_count: 52,
              price_level: 2,
              phone: "+34 988 123 456",
              website: "https://example.com/rodriguez-abogados",
              types: ["lawyer", "legal_services"],
              reviews: [
                %{
                  author: "María García",
                  rating: 5,
                  text: "Excelente servicio, muy profesionales. They also speak English!",
                  language: "es"
                },
                %{
                  author: "John Smith",
                  rating: 5,
                  text: "Helped me with my NIE and residency. Great English speakers.",
                  language: "en"
                }
              ]
            },
            %{
              place_id: "mock_lawyer_2",
              name: "Asesoría Legal Galicia",
              address: "Plaza Mayor 12, Ourense",
              latitude: base_lat - 0.001,
              longitude: base_lng + 0.002,
              rating: 4.3,
              review_count: 28,
              price_level: 2,
              phone: "+34 988 234 567",
              types: ["lawyer", "legal_services"]
            }
          ]

        String.contains?(query_lower, "restaurant") or String.contains?(query_lower, "restaurante") ->
          [
            %{
              place_id: "mock_restaurant_1",
              name: "Casa Pepe Tapas",
              address: "Rúa do Paseo 8, Ourense",
              latitude: base_lat + 0.003,
              longitude: base_lng - 0.001,
              rating: 4.6,
              review_count: 234,
              price_level: 2,
              phone: "+34 988 345 678",
              types: ["restaurant", "tapas_bar"],
              reviews: [
                %{author: "Pedro M.", rating: 5, text: "El mejor pulpo de Ourense", language: "es"},
                %{
                  author: "Sarah K.",
                  rating: 4,
                  text: "Staff speaks some English. Delicious food!",
                  language: "en"
                }
              ]
            }
          ]

        String.contains?(query_lower, "doctor") or String.contains?(query_lower, "médico") ->
          [
            %{
              place_id: "mock_doctor_1",
              name: "Clínica Médica Central",
              address: "Avenida de Portugal 23, Ourense",
              latitude: base_lat - 0.002,
              longitude: base_lng - 0.002,
              rating: 4.4,
              review_count: 89,
              price_level: 2,
              phone: "+34 988 456 789",
              types: ["doctor", "health"],
              reviews: [
                %{
                  author: "Ana B.",
                  rating: 5,
                  text: "Dr. Fernández habla inglés perfectamente",
                  language: "es"
                }
              ]
            }
          ]

        true ->
          [
            %{
              place_id: "mock_generic_1",
              name: "Negocio Local #{:rand.uniform(100)}",
              address: "Calle Principal #{:rand.uniform(50)}, Ourense",
              latitude: base_lat + (:rand.uniform() - 0.5) * 0.01,
              longitude: base_lng + (:rand.uniform() - 0.5) * 0.01,
              rating: 3.5 + :rand.uniform() * 1.5,
              review_count: :rand.uniform(100),
              types: ["establishment"]
            }
          ]
      end

    # Add common fields
    Enum.map(businesses, fn biz ->
      Map.merge(biz, %{
        google_maps_url: "https://maps.google.com/?cid=#{biz.place_id}",
        business_status: "OPERATIONAL",
        raw_data: %{source: "mock"}
      })
    end)
  end
end
