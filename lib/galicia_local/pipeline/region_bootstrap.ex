defmodule GaliciaLocal.Pipeline.RegionBootstrap do
  @moduledoc """
  Bootstrap a new region using Claude CLI.

  Given just a region name (e.g., "Portugal"), generates:
  - Region attributes (country_code, slug, timezone, locales, tagline)
  - Settings (phrases, cultural_tips, enrichment_context)
  - City suggestions (name, province, lat/lon, population)
  - Discovery URL suggestions for web crawling
  """

  require Logger

  alias GaliciaLocal.AI.ClaudeCLI
  alias GaliciaLocal.Directory.Region
  alias GaliciaLocal.Scraper.Tavily

  @doc """
  Generate region attributes and settings from a region name using Claude.
  Returns `{:ok, map}` with keys matching Region attributes, or `{:error, reason}`.
  """
  def enrich_region(name) do
    prompt = region_enrichment_prompt(name)

    case call_claude(prompt) do
      {:ok, response} -> parse_region_response(response)
      {:error, _} = error -> error
    end
  end

  @doc """
  Suggest cities for a region using Claude.
  Returns `{:ok, [city_map]}` or `{:error, reason}`.
  """
  def suggest_cities(region_name, country_code) do
    prompt = city_suggestion_prompt(region_name, country_code)

    case call_claude(prompt) do
      {:ok, response} -> parse_cities_response(response)
      {:error, _} = error -> error
    end
  end

  @doc """
  Suggest discovery URLs for all cities in a region using Claude.
  Returns `{:ok, [%{city_name: name, urls: [%{url, name, description}]}]}` or `{:error, reason}`.
  """
  def suggest_discovery_urls(region_id) do
    region = Region.get_by_id!(region_id) |> Ash.load!(:cities)

    prompt = discovery_urls_prompt(region.name, region.country_code, Enum.map(region.cities, & &1.name))

    case call_claude(prompt) do
      {:ok, response} -> parse_discovery_urls_response(response, region.cities)
      {:error, _} = error -> error
    end
  end

  @doc """
  Start discovery crawls for the given URLs grouped by city.
  Expects a list of `%{city_id: id, urls: [url_string]}`.
  Returns `{:ok, %{crawls_started: n, cities: n}}`.
  """
  def start_discovery_crawls(url_groups, region_id) do
    crawls =
      Enum.map(url_groups, fn %{city_id: city_id, urls: urls} ->
        case GaliciaLocal.Scraper.crawl_directory(urls,
               city_id: city_id,
               region_id: region_id,
               max_pages: 200
             ) do
          {:ok, crawl_id} ->
            Logger.info("Started discovery crawl #{crawl_id} for city #{city_id}")

            # Queue processing worker with 10-minute delay to let crawl finish
            %{crawl_id: crawl_id}
            |> GaliciaLocal.Workers.DiscoveryProcessWorker.new(
              scheduled_at: DateTime.add(DateTime.utc_now(), 10, :minute)
            )
            |> Oban.insert()

            {:ok, crawl_id}

          {:error, reason} ->
            Logger.warning("Failed to start crawl for city #{city_id}: #{inspect(reason)}")
            {:error, reason}
        end
      end)

    started = Enum.count(crawls, &match?({:ok, _}, &1))

    {:ok, %{crawls_started: started, cities: length(url_groups)}}
  end

  @doc """
  Start Overpass import for all cities in a region.
  Queues one OverpassImportWorker per city. Returns `{:ok, %{jobs_queued: n}}`.
  """
  def start_overpass_import(region_id) do
    region = Region.get_by_id!(region_id) |> Ash.load!(:cities)

    jobs =
      Enum.with_index(region.cities, 1)
      |> Enum.map(fn {city, idx} ->
        # Stagger jobs by 60 seconds each to respect Overpass rate limits (~2 req/min)
        %{city_id: city.id, region_id: region_id}
        |> GaliciaLocal.Workers.OverpassImportWorker.new(
          scheduled_at: DateTime.add(DateTime.utc_now(), idx * 60, :second)
        )
        |> Oban.insert()
      end)

    queued = Enum.count(jobs, &match?({:ok, _}, &1))
    Logger.info("OverpassImport: queued #{queued} jobs for region #{region.name}")

    {:ok, %{jobs_queued: queued, cities: length(region.cities)}}
  end

  @doc """
  Suggest discovery URLs for all cities using Tavily search (replaces Claude URL suggestion).
  Returns `{:ok, [%{city_id, city_name, urls: [%{url, name, description, selected}]}]}`.

  Uses Task.async_stream with max_concurrency: 3 for parallel lookups.
  """
  def suggest_discovery_urls_tavily(region_id) do
    region = Region.get_by_id!(region_id) |> Ash.load!(:cities)

    results =
      region.cities
      |> Task.async_stream(
        fn city ->
          case Tavily.search_directory_sites(city.name, region.country_code) do
            {:ok, urls} ->
              %{city_id: city.id, city_name: city.name, urls: urls}

            {:error, reason} ->
              Logger.warning("Tavily search failed for #{city.name}: #{inspect(reason)}")
              %{city_id: city.id, city_name: city.name, urls: []}
          end
        end,
        max_concurrency: 3,
        timeout: 60_000,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, _} -> nil
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.filter(fn r -> r.urls != [] end)

    {:ok, results}
  end

  # --- Prompts ---

  defp region_enrichment_prompt(name) do
    """
    You are helping build StartLocal.app, an expat-focused local business directory.
    Given the region/country name "#{name}", generate complete region data.

    Return ONLY a JSON object (no markdown, no explanation) with this exact structure:

    {
      "name": "Display Name",
      "slug": "url-friendly-slug",
      "country_code": "XX",
      "default_locale": "en",
      "supported_locales": ["en", "local_lang_code"],
      "timezone": "Continent/City",
      "tagline": "Short evocative tagline for expats (max 60 chars)",
      "settings": {
        "phrases": [
          {"local": "Local phrase", "english": "English translation", "usage": "When to use it"}
        ],
        "cultural_tips": [
          {"icon": "heroicon-name", "title": "Short Title", "tip": "Practical tip for newcomers"}
        ],
        "enrichment_context": {
          "name": "Region Name",
          "country": "Country Name",
          "main_language": "Official Language",
          "local_language": "Regional language if any, null otherwise",
          "language_code": "xx",
          "local_greeting": "Common greeting",
          "typical_business": "Description of typical local business",
          "food_examples": "local food items, comma separated",
          "cultural_examples": [
            "Cultural insight relevant for expats",
            "Another cultural insight"
          ]
        }
      }
    }

    Guidelines:
    - phrases: 8-10 essential phrases for newcomers. Include greetings, thanks, goodbye, cheers, enjoy your meal
    - cultural_tips: 6 practical tips. Use heroicon names: clock, sun, sparkles, banknotes, hand-raised, fire, chat-bubble-left-right, truck, cake, calendar, heart, map-pin
    - supported_locales: always include "en" plus the main local language
    - tagline: evocative, highlights what makes this place special for expats
    - enrichment_context: used to give AI context when enriching business listings

    Examples of existing regions for consistency:
    - Galicia: slug "galicia", country_code "ES", locales ["en", "es"], timezone "Europe/Madrid", tagline "Celtic heritage, incredible seafood, warm communities"
    - Netherlands: slug "netherlands", country_code "NL", locales ["en", "nl"], timezone "Europe/Amsterdam", tagline "Cycling culture, canals, welcoming expat scene"
    """
  end

  defp city_suggestion_prompt(region_name, country_code) do
    """
    You are helping build StartLocal.app, an expat-focused local business directory for "#{region_name}" (#{country_code}).

    List the top 15-20 cities and towns that expats commonly move to in #{region_name}.
    Include a mix of major cities and popular smaller towns.

    Return ONLY a JSON array (no markdown, no explanation) with this structure:

    [
      {
        "name": "City Name (in English if commonly known, otherwise local name)",
        "slug": "url-friendly-slug",
        "province": "Province/State/Region name",
        "latitude": 41.1579,
        "longitude": -8.6291,
        "population": 250000,
        "featured": true
      }
    ]

    Guidelines:
    - slug: lowercase, hyphens, no accents (e.g., "porto", "santiago-de-compostela")
    - province: the administrative region/province the city belongs to
    - latitude/longitude: accurate to 4 decimal places
    - population: approximate current population (city proper, not metro)
    - featured: true for the top 5-6 most popular cities for expats, false for others
    - Sort by population descending
    - Include the capital and major economic centers
    - Include popular retirement/digital nomad destinations
    """
  end

  defp discovery_urls_prompt(region_name, country_code, city_names) do
    cities_list = Enum.join(city_names, ", ")

    """
    You are helping build StartLocal.app, an expat-focused local business directory for "#{region_name}" (#{country_code}).

    For EACH of the following cities, suggest 3-6 URLs of local business directory websites
    that we can crawl to discover businesses (restaurants, shops, services, professionals, etc.):

    Cities: #{cities_list}

    Return ONLY a JSON object (no markdown, no explanation) with this structure:

    {
      "cities": [
        {
          "city": "City Name",
          "urls": [
            {"url": "https://example.com/businesses/cityname", "name": "Site Name", "description": "What it lists"}
          ]
        }
      ]
    }

    Guidelines:
    - Include country-specific yellow pages / business directories (e.g., Páginas Amarelas for PT, Gouden Gids for NL)
    - Include local chamber of commerce or municipal business listings
    - Include popular review sites with local business pages (TripAdvisor city page, Yelp equivalent)
    - URLs should point to pages that LIST businesses (search results, category pages), not homepages
    - Make URLs as specific to the city as possible (include city name in URL path/query)
    - Prefer URLs that will have many business listings when crawled
    - Do NOT include Google Maps URLs (we handle that separately)
    - Only include real, working websites you're confident exist
    """
  end

  # --- Claude Communication ---

  defp call_claude(prompt) do
    if ClaudeCLI.cli_available?() do
      ClaudeCLI.complete(prompt)
    else
      Logger.info("Claude CLI not available, falling back to API")
      case GaliciaLocal.AI.Claude.complete(prompt) do
        {:ok, response} -> {:ok, response}
        error -> error
      end
    end
  end

  # --- Response Parsing ---

  defp parse_region_response(response) do
    response
    |> extract_json()
    |> case do
      {:ok, %{"name" => _, "slug" => _, "country_code" => _} = data} ->
        {:ok, data}

      {:ok, _other} ->
        {:error, :invalid_structure}

      {:error, _} = error ->
        error
    end
  end

  defp parse_cities_response(response) do
    response
    |> extract_json()
    |> case do
      {:ok, cities} when is_list(cities) ->
        valid_cities =
          Enum.filter(cities, fn c ->
            is_binary(c["name"]) and is_binary(c["slug"])
          end)

        if valid_cities == [] do
          {:error, :no_valid_cities}
        else
          {:ok, valid_cities}
        end

      {:ok, _} ->
        {:error, :expected_array}

      {:error, _} = error ->
        error
    end
  end

  defp parse_discovery_urls_response(response, cities) do
    response
    |> extract_json()
    |> case do
      {:ok, %{"cities" => city_urls}} when is_list(city_urls) ->
        # Match Claude's city names back to our city records
        results =
          Enum.map(city_urls, fn %{"city" => city_name, "urls" => urls} ->
            city = Enum.find(cities, fn c -> String.downcase(c.name) == String.downcase(city_name) end)

            %{
              city_id: city && city.id,
              city_name: city_name,
              urls: Enum.map(urls || [], fn u ->
                %{
                  "url" => u["url"],
                  "name" => u["name"] || "Unknown",
                  "description" => u["description"] || "",
                  "selected" => true
                }
              end)
            }
          end)
          |> Enum.filter(fn r -> r.city_id != nil and r.urls != [] end)

        {:ok, results}

      {:ok, _} ->
        {:error, :unexpected_structure}

      {:error, _} = error ->
        error
    end
  end

  defp extract_json(text) do
    # Try multiple strategies to find JSON in Claude's response:
    # 1. Markdown code blocks
    # 2. Raw text as-is
    # 3. First { to last } (JSON object buried in text)
    # 4. First [ to last ] (JSON array buried in text)
    candidates =
      [
        case Regex.run(~r/```(?:json)?\s*\n?([\s\S]*?)\n?```/, text) do
          [_, json] -> String.trim(json)
          _ -> nil
        end,
        String.trim(text),
        slice_outer(text, "{", "}"),
        slice_outer(text, "[", "]")
      ]
      |> Enum.reject(&is_nil/1)

    Enum.find_value(candidates, {:error, {:json_parse_error, String.slice(text, 0, 200)}}, fn
      candidate ->
        case Jason.decode(candidate) do
          {:ok, data} -> {:ok, data}
          {:error, _} -> nil
        end
    end)
  end

  defp slice_outer(text, open, close) do
    with {start, _} <- :binary.match(text, open),
         matches when matches != [] <- :binary.matches(text, close) do
      {last, len} = List.last(matches)
      binary_part(text, start, last - start + len)
    else
      _ -> nil
    end
  end
end
