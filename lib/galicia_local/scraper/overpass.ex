defmodule GaliciaLocal.Scraper.Overpass do
  @moduledoc """
  OpenStreetMap Overpass API client for discovering businesses.

  Two modes of operation:
  1. **City-wide query** (`query_businesses/1`) — queries ALL business-relevant tags
     for a city by name using Overpass area search. Returns raw OSM elements.
  2. **Category search** (`search/2`) — queries a specific category within a bounding box.
  3. **Import** (`import_businesses/2`) — queries + creates Business records in the DB.

  ## Examples

      # Query all businesses in a city
      Overpass.query_businesses("Pontevedra")

      # Import businesses for a city into the DB
      Overpass.import_businesses(city_id, region_id)

      # Search for restaurants in Amsterdam area (bbox)
      Overpass.search("restaurants", {52.3, 4.8, 52.4, 5.0})
  """

  require Logger

  alias GaliciaLocal.Directory.Business

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
    "municipalities" => [{"amenity", "townhall"}, {"office", "government"}],
    "camping" => [{"tourism", "camp_site"}]
  }

  # Reverse mapping: OSM tag value → category slug (for city-wide import)
  @osm_category_map %{
    {"shop", "supermarket"} => "supermarkets",
    {"shop", "bakery"} => "bakeries",
    {"shop", "butcher"} => "butchers",
    {"shop", "hairdresser"} => "hair-salons",
    {"shop", "beauty"} => "hair-salons",
    {"shop", "car_repair"} => "car-services",
    {"shop", "car"} => "car-services",
    {"shop", "wine"} => "wineries",
    {"shop", "marketplace"} => "markets",
    {"amenity", "cafe"} => "cafes",
    {"amenity", "restaurant"} => "restaurants",
    {"amenity", "dentist"} => "dentists",
    {"amenity", "doctors"} => "doctors",
    {"amenity", "hospital"} => "hospitals",
    {"amenity", "veterinary"} => "veterinarians",
    {"amenity", "library"} => "libraries",
    {"amenity", "marketplace"} => "markets",
    {"amenity", "language_school"} => "language-schools",
    {"amenity", "music_school"} => "music-schools",
    {"amenity", "school"} => "elementary-schools",
    {"amenity", "townhall"} => "municipalities",
    {"amenity", "bar"} => "cider-houses",
    {"amenity", "pub"} => "cider-houses",
    {"craft", "electrician"} => "electricians",
    {"craft", "plumber"} => "plumbers",
    {"craft", "winery"} => "wineries",
    {"office", "estate_agent"} => "real-estate",
    {"office", "lawyer"} => "lawyers",
    {"office", "notary"} => "lawyers",
    {"office", "accountant"} => "accountants",
    {"office", "tax_advisor"} => "accountants",
    {"office", "government"} => "municipalities",
    {"office", "language_school"} => "language-schools",
    {"healthcare", "doctor"} => "doctors",
    {"healthcare", "dentist"} => "dentists",
    {"tourism", "camp_site"} => "camping"
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

  # --- City-wide query + import ---

  @doc """
  Query ALL businesses in a city by name using Overpass area search.
  Returns `{:ok, [normalized_element]}` or `{:error, reason}`.

  Uses `area["name"="{city}"]["admin_level"~"6|7|8"]` for flexible city matching,
  then queries all business-relevant OSM tags within that area.
  """
  def query_businesses(city_name, _opts \\ []) do
    query = build_city_query(city_name)
    Logger.info("Overpass city query for #{city_name}: #{String.length(query)} chars")

    case do_request(query) do
      {:ok, elements} ->
        normalized =
          elements
          |> Enum.filter(&has_name?/1)
          |> Enum.map(&normalize_element/1)

        Logger.info("Overpass found #{length(normalized)} businesses in #{city_name}")
        {:ok, normalized}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Import businesses from OpenStreetMap for a city into the database.
  Returns `{:ok, %{created: n, skipped: n, failed: n}}` or `{:error, reason}`.
  """
  def import_businesses(city_id, region_id) do
    city = load_city(city_id)

    if is_nil(city) do
      {:error, :city_not_found}
    else
      case query_businesses(city.name) do
        {:ok, elements} ->
          category_ids = load_category_ids()
          results = Enum.map(elements, &create_business(&1, city, region_id, category_ids))

          created = Enum.count(results, &(&1 == :created))
          skipped = Enum.count(results, &(&1 == :skipped))
          failed = Enum.count(results, &(&1 == :failed))

          Logger.info(
            "Overpass import for #{city.name}: #{created} created, #{skipped} skipped, #{failed} failed"
          )

          {:ok, %{created: created, skipped: skipped, failed: failed}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp build_city_query(city_name) do
    # Use multiple area lookups: admin boundaries (6-10) and place nodes.
    # Small towns may only have place=town/village, not admin_level boundaries.
    """
    [out:json][timeout:60];
    (
      area["name"="#{city_name}"]["admin_level"~"^(6|7|8|9|10)$"];
      area["name"="#{city_name}"]["place"~"^(city|town|village|municipality)$"];
    )->.searchArea;
    (
      nwr["name"]["shop"](area.searchArea);
      nwr["name"]["amenity"~"^(restaurant|cafe|bar|pub|doctors|dentist|hospital|veterinary|library|marketplace|language_school|music_school|school|townhall)$"](area.searchArea);
      nwr["name"]["craft"](area.searchArea);
      nwr["name"]["office"~"^(estate_agent|lawyer|notary|accountant|tax_advisor|government|language_school)$"](area.searchArea);
      nwr["name"]["healthcare"](area.searchArea);
      nwr["name"]["tourism"="camp_site"](area.searchArea);
    );
    out center tags;
    """
  end

  defp load_city(city_id) do
    case GaliciaLocal.Repo.query!(
           "SELECT id::text, name, region_id::text FROM cities WHERE id = $1",
           [Ecto.UUID.dump!(city_id)]
         ) do
      %{rows: [[id, name, rid]]} -> %{id: id, name: name, region_id: rid}
      _ -> nil
    end
  end

  defp load_category_ids do
    %{rows: rows} =
      GaliciaLocal.Repo.query!("SELECT slug, id::text FROM categories ORDER BY slug")

    Map.new(rows, fn [slug, id] -> {slug, id} end)
  end

  defp create_business(element, city, region_id, category_ids) do
    category_slug = detect_category(element.raw_tags)
    category_id = category_ids[category_slug]

    if is_nil(category_id) do
      :skipped
    else
      slug = generate_slug(element.name)

      attrs = %{
        name: element.name,
        slug: slug,
        address: element.address,
        phone: element.phone,
        website: element.website,
        email: element.email,
        latitude: element.latitude && Decimal.new("#{element.latitude}"),
        longitude: element.longitude && Decimal.new("#{element.longitude}"),
        opening_hours: element.opening_hours,
        google_maps_url: element.google_maps_url,
        status: :pending,
        source: :openstreetmap,
        raw_data:
          %{
            osm_id: element.osm_id,
            osm_tags: element.raw_tags,
            imported_at: DateTime.utc_now() |> DateTime.to_iso8601()
          }
          |> then(fn data ->
            if element.extracted_hints, do: Map.put(data, "extracted_hints", element.extracted_hints), else: data
          end),
        city_id: city.id,
        category_id: category_id,
        region_id: region_id
      }

      case Business.create(attrs) do
        {:ok, _business} -> :created
        {:error, %Ash.Error.Invalid{}} -> :skipped
        {:error, _reason} -> :failed
      end
    end
  end

  defp detect_category(tags) do
    # Try each known OSM tag pair against the reverse mapping
    Enum.find_value(@osm_category_map, fn {{key, value}, slug} ->
      if tags[key] == value, do: slug
    end)
  end

  defp generate_slug(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/\s+/, "-")
    |> String.trim("-")
    |> String.slice(0, 100)
  end

  # --- Category-based bbox search ---

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
      raw_tags: tags,
      extracted_hints: extract_hints(tags)
    }
  end

  defp extract_hints(tags) do
    hints = %{}

    hints = if tags["cuisine"], do: Map.put(hints, "cuisine", tags["cuisine"]), else: hints
    hints = if tags["description"], do: Map.put(hints, "description", tags["description"]), else: hints
    hints = if tags["operator"], do: Map.put(hints, "operator", tags["operator"]), else: hints
    hints = if tags["brand"], do: Map.put(hints, "brand", tags["brand"]), else: hints
    hints = if tags["wheelchair"], do: Map.put(hints, "wheelchair", tags["wheelchair"]), else: hints
    hints = if tags["takeaway"], do: Map.put(hints, "takeaway", tags["takeaway"]), else: hints
    hints = if tags["delivery"], do: Map.put(hints, "delivery", tags["delivery"]), else: hints
    hints = if tags["outdoor_seating"], do: Map.put(hints, "outdoor_seating", tags["outdoor_seating"]), else: hints
    hints = if tags["internet_access"], do: Map.put(hints, "internet_access", tags["internet_access"]), else: hints

    # Social media
    social =
      Enum.reduce(tags, %{}, fn
        {"contact:instagram", v}, acc -> Map.put(acc, "instagram", v)
        {"contact:facebook", v}, acc -> Map.put(acc, "facebook", v)
        {"contact:twitter", v}, acc -> Map.put(acc, "twitter", v)
        _, acc -> acc
      end)

    hints = if map_size(social) > 0, do: Map.put(hints, "social_media", social), else: hints

    # Payment methods
    payment_cash_only =
      Enum.any?(tags, fn
        {"payment:cash", "yes"} -> true
        _ -> false
      end) and
        not Enum.any?(tags, fn
          {"payment:credit_cards", "yes"} -> true
          {"payment:debit_cards", "yes"} -> true
          _ -> false
        end)

    hints = if payment_cash_only, do: Map.put(hints, "cash_only", true), else: hints

    # Diet options (for restaurants/cafes)
    diets =
      Enum.reduce(tags, [], fn
        {"diet:" <> diet, "yes"}, acc -> [diet | acc]
        _, acc -> acc
      end)

    hints = if diets != [], do: Map.put(hints, "diet_options", Enum.reverse(diets)), else: hints

    if map_size(hints) > 0, do: hints, else: nil
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
