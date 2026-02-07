defmodule GaliciaLocal.Scraper.Overpass do
  @moduledoc """
  OpenStreetMap Overpass API client for discovering businesses.

  Free alternative to Google Places API. Uses the public Overpass API
  to query OSM data by category within a geographic bounding box.

  ## Examples

      # Search for restaurants in Amsterdam area
      Overpass.search("restaurants", {52.3, 4.8, 52.4, 5.0})

      # Check if a category has OSM mappings
      Overpass.has_tags?("restaurants")  #=> true
  """

  require Logger

  @overpass_url "https://overpass-api.de/api/interpreter"
  @request_timeout 60_000

  # Maps category slugs to Overpass QL filter expressions.
  # Each category can have multiple node/way queries to cover different tagging conventions.
  @osm_tags %{
    "restaurants" => [{"amenity", "restaurant"}],
    "cafes" => [{"amenity", "cafe"}],
    "bakeries" => [{"shop", "bakery"}],
    "butchers" => [{"shop", "butcher"}],
    "supermarkets" => [{"shop", "supermarket"}],
    "markets" => [{"amenity", "marketplace"}, {"shop", "marketplace"}],
    "wineries" => [{"craft", "winery"}, {"shop", "wine"}],
    "cider-houses" => [{"amenity", "bar"}, {"amenity", "pub"}],
    "doctors" => [{"amenity", "doctors"}, {"healthcare", "doctor"}],
    "dentists" => [{"amenity", "dentist"}, {"healthcare", "dentist"}],
    "hospitals" => [{"amenity", "hospital"}],
    "veterinarians" => [{"amenity", "veterinary"}],
    "hair-salons" => [{"shop", "hairdresser"}, {"shop", "beauty"}],
    "libraries" => [{"amenity", "library"}],
    "elementary-schools" => [{"amenity", "school"}],
    "high-schools" => [{"amenity", "school"}],
    "music-schools" => [{"amenity", "music_school"}, {"leisure", "music_school"}],
    "language-schools" => [{"office", "language_school"}, {"amenity", "language_school"}],
    "lawyers" => [{"office", "lawyer"}, {"office", "notary"}],
    "accountants" => [{"office", "accountant"}, {"office", "tax_advisor"}],
    "electricians" => [{"craft", "electrician"}],
    "plumbers" => [{"craft", "plumber"}],
    "car-services" => [{"shop", "car_repair"}, {"shop", "car"}],
    "real-estate" => [{"office", "estate_agent"}],
    "municipalities" => [{"amenity", "townhall"}, {"office", "government"}]
  }

  @day_map %{
    "Mo" => "monday",
    "Tu" => "tuesday",
    "We" => "wednesday",
    "Th" => "thursday",
    "Fr" => "friday",
    "Sa" => "saturday",
    "Su" => "sunday"
  }

  @day_order ~w(Mo Tu We Th Fr Sa Su)

  @doc """
  Search for businesses of a given category within a bounding box.

  Returns `{:ok, [normalized_element]}` or `{:error, reason}`.

  ## Parameters
    - `category_slug` - Category slug matching a key in the OSM tag mappings
    - `bbox` - `{south, west, north, east}` bounding box tuple
  """
  @spec search(String.t(), {number, number, number, number}) :: {:ok, list(map())} | {:error, term()}
  def search(category_slug, {south, west, north, east} = _bbox) do
    case tags_for_category(category_slug) do
      nil ->
        {:error, :no_osm_tags}

      tags ->
        query = build_query(tags, south, west, north, east)
        Logger.info("Overpass query for #{category_slug}: #{String.length(query)} chars")

        case do_request(query) do
          {:ok, elements} ->
            normalized =
              elements
              |> Enum.filter(&has_name?/1)
              |> Enum.map(&normalize_element/1)

            Logger.info("Overpass found #{length(normalized)} #{category_slug} in bbox")
            {:ok, normalized}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Get the OSM tag filters for a category slug.
  Returns nil if the category has no mapping.
  """
  @spec tags_for_category(String.t()) :: list({String.t(), String.t()}) | nil
  def tags_for_category(category_slug) do
    Map.get(@osm_tags, category_slug)
  end

  @doc """
  Check if a category has OSM tag mappings.
  """
  @spec has_tags?(String.t()) :: boolean()
  def has_tags?(category_slug) do
    Map.has_key?(@osm_tags, category_slug)
  end

  # --- Private ---

  defp build_query(tags, south, west, north, east) do
    bbox = "#{south},#{west},#{north},#{east}"

    filters =
      tags
      |> Enum.flat_map(fn {key, value} ->
        [
          "node[\"#{key}\"=\"#{value}\"](#{bbox});",
          "way[\"#{key}\"=\"#{value}\"](#{bbox});"
        ]
      end)
      |> Enum.join("\n  ")

    """
    [out:json][timeout:60];
    (
      #{filters}
    );
    out center tags;
    """
  end

  defp do_request(query) do
    case Req.post(@overpass_url,
           form: [data: query],
           receive_timeout: @request_timeout,
           headers: [{"user-agent", "GaliciaLocalBot/1.0 (business directory)"}]
         ) do
      {:ok, %{status: 200, body: %{"elements" => elements}}} ->
        {:ok, elements}

      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        # Sometimes Overpass returns HTML error pages with 200 status
        Logger.error("Overpass returned non-JSON response: #{String.slice(body, 0, 200)}")
        {:error, :invalid_response}

      {:ok, %{status: 429}} ->
        Logger.warning("Overpass rate limited, retry later")
        {:error, :rate_limited}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Overpass error #{status}: #{inspect(body) |> String.slice(0, 200)}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.error("Overpass request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp has_name?(%{"tags" => %{"name" => name}}) when is_binary(name) and name != "", do: true
  defp has_name?(_), do: false

  defp normalize_element(element) do
    tags = element["tags"] || %{}
    {lat, lon} = extract_coordinates(element)

    %{
      osm_id: "#{element["type"]}/#{element["id"]}",
      name: tags["name"],
      address: build_address(tags),
      phone: tags["phone"] || tags["contact:phone"],
      website: tags["website"] || tags["contact:website"] || tags["url"],
      email: tags["email"] || tags["contact:email"],
      latitude: lat,
      longitude: lon,
      opening_hours: parse_opening_hours(tags["opening_hours"]),
      opening_hours_raw: tags["opening_hours"],
      google_maps_url: build_google_maps_url(lat, lon),
      raw_tags: tags
    }
  end

  defp extract_coordinates(%{"type" => "node", "lat" => lat, "lon" => lon}), do: {lat, lon}
  defp extract_coordinates(%{"center" => %{"lat" => lat, "lon" => lon}}), do: {lat, lon}
  defp extract_coordinates(_), do: {nil, nil}

  defp build_address(tags) do
    street = tags["addr:street"]
    number = tags["addr:housenumber"]

    street_line =
      case {street, number} do
        {nil, _} -> nil
        {s, nil} -> s
        {s, n} -> "#{s} #{n}"
      end

    [street_line, tags["addr:postcode"], tags["addr:city"]]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(", ")
    |> case do
      "" -> nil
      address -> address
    end
  end

  defp build_google_maps_url(nil, _), do: nil
  defp build_google_maps_url(_, nil), do: nil

  defp build_google_maps_url(lat, lon) do
    "https://www.google.com/maps/search/?api=1&query=#{lat},#{lon}"
  end

  @doc false
  def parse_opening_hours(nil), do: nil
  def parse_opening_hours("24/7"), do: %{"monday" => "00:00-24:00", "tuesday" => "00:00-24:00", "wednesday" => "00:00-24:00", "thursday" => "00:00-24:00", "friday" => "00:00-24:00", "saturday" => "00:00-24:00", "sunday" => "00:00-24:00"}

  def parse_opening_hours(raw) when is_binary(raw) do
    result =
      raw
      |> String.split(";")
      |> Enum.map(&String.trim/1)
      |> Enum.reduce(%{}, fn segment, acc ->
        case parse_segment(segment) do
          {:ok, day_hours} -> Map.merge(acc, day_hours)
          :skip -> acc
        end
      end)

    if map_size(result) == 0, do: nil, else: result
  end

  defp parse_segment(segment) do
    # Match patterns like "Mo-Fr 09:00-17:00" or "Sa 10:00-14:00"
    case Regex.run(~r/^([A-Za-z,-]+)\s+(.+)$/, segment) do
      [_, days_str, hours] ->
        days = expand_days(days_str)

        if days == [] do
          :skip
        else
          {:ok, Map.new(days, fn day -> {day, hours} end)}
        end

      _ ->
        :skip
    end
  end

  defp expand_days(days_str) do
    days_str
    |> String.split(",")
    |> Enum.flat_map(&expand_day_range/1)
  end

  defp expand_day_range(range) do
    case String.split(String.trim(range), "-") do
      [from, to] ->
        from_idx = Enum.find_index(@day_order, &(&1 == from))
        to_idx = Enum.find_index(@day_order, &(&1 == to))

        if from_idx && to_idx && to_idx >= from_idx do
          @day_order
          |> Enum.slice(from_idx..to_idx)
          |> Enum.map(&Map.get(@day_map, &1))
          |> Enum.reject(&is_nil/1)
        else
          []
        end

      [single] ->
        case Map.get(@day_map, String.trim(single)) do
          nil -> []
          day -> [day]
        end

      _ ->
        []
    end
  end
end
