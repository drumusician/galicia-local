defmodule GaliciaLocal.Pipeline.RegionBootstrap do
  @moduledoc """
  Bootstrap a new region using Claude CLI.

  Given just a region name (e.g., "Portugal"), generates:
  - Region attributes (country_code, slug, timezone, locales, tagline)
  - Settings (phrases, cultural_tips, enrichment_context)
  - City suggestions (name, province, lat/lon, population)

  Then orchestrates Google Places discovery across all cities × categories.
  """

  require Logger

  alias GaliciaLocal.AI.ClaudeCLI
  alias GaliciaLocal.Directory.{Region, City, Category}

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
  Queue Google Places discovery for all cities in a region.
  Returns `{:ok, %{cities: n, categories: n, jobs_queued: n}}`.
  """
  def discover_region(region_id) do
    region = Region.get_by_id!(region_id) |> Ash.load!(:cities)
    categories = Category.list!()

    results =
      for city <- region.cities, category <- categories do
        case GaliciaLocal.Scraper.search_google_places(city, category) do
          {:ok, jobs} -> length(jobs)
          {:error, reason} ->
            Logger.warning("Discovery failed for #{city.name}/#{category.name}: #{inspect(reason)}")
            0
        end
      end

    {:ok, %{
      cities: length(region.cities),
      categories: length(categories),
      jobs_queued: Enum.sum(results)
    }}
  end

  @doc """
  Estimate the cost of discovering a region via Google Places.
  """
  def estimate_discovery_cost(city_count, category_count) do
    # Average ~3 sub-queries per category search
    avg_sub_queries = 3
    searches = city_count * category_count * avg_sub_queries
    # $0.032 per search + $0.035 per detail (avg 5 results per search)
    cost_per_search = 0.032
    cost_per_detail = 0.035
    avg_results = 5

    search_cost = searches * cost_per_search
    detail_cost = searches * avg_results * cost_per_detail
    total = search_cost + detail_cost

    %{
      searches: searches,
      estimated_businesses: searches * avg_results,
      estimated_cost_usd: Float.round(total, 2)
    }
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

  defp extract_json(text) do
    # Try to find JSON in the response (Claude sometimes wraps in markdown code blocks)
    json_text =
      case Regex.run(~r/```(?:json)?\s*\n?([\s\S]*?)\n?```/, text) do
        [_, json] -> String.trim(json)
        _ -> String.trim(text)
      end

    case Jason.decode(json_text) do
      {:ok, data} -> {:ok, data}
      {:error, _} -> {:error, {:json_parse_error, String.slice(json_text, 0, 200)}}
    end
  end
end
