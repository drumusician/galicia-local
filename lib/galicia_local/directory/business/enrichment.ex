defmodule GaliciaLocal.Directory.Business.Enrichment do
  @moduledoc """
  Shared enrichment logic for building prompts and parsing LLM responses.

  Used by `EnrichWithLLM` which handles both API and CLI enrichment paths.
  """

  require Logger

  alias GaliciaLocal.Scraper.Workers.{WebsiteCrawlWorker, WebSearchWorker}

  # Fallback region context when settings are not populated
  @fallback_context %{
    "galicia" => %{
      "name" => "Galicia",
      "country" => "Spain",
      "main_language" => "Spanish",
      "local_language" => "Galician (Galego)",
      "language_code" => "es",
      "local_greeting" => "Bos días",
      "cultural_examples" => [
        "Pulperías are central to Galician social life",
        "The siesta is real - many shops close 2-5pm",
        "Tapas are often free with drinks",
        "Galicians value personal relationships - expect friendly chat"
      ],
      "food_examples" => "pulpo, tapas, marisquería",
      "typical_business" => "traditional family-run tapas bar"
    },
    "netherlands" => %{
      "name" => "Netherlands",
      "country" => "Netherlands",
      "main_language" => "Dutch",
      "local_language" => nil,
      "language_code" => "nl",
      "local_greeting" => "Hoi or Goedemorgen",
      "cultural_examples" => [
        "Dutch directness is normal - it's not rude, just honest",
        "Most shops close early (17:00-18:00) and on Sundays",
        "Appointments are everything - always book ahead",
        "Splitting the bill (going Dutch) is completely normal"
      ],
      "food_examples" => "stroopwafels, bitterballen, Indonesian food",
      "typical_business" => "local family bakery or brown café (bruin café)"
    }
  }

  @doc """
  Loads business relationships needed for enrichment.
  """
  def load_relationships(business) do
    case Ash.load(business, [:city, :category, :region]) do
      {:ok, loaded} -> loaded
      _ -> business
    end
  end

  @doc """
  Loads research data (website crawl + web search) for a business.
  """
  def load_research_data(business_id) do
    website_data =
      case WebsiteCrawlWorker.load_website_results(business_id) do
        {:ok, data} -> data
        {:error, _} -> nil
      end

    search_data =
      case WebSearchWorker.load_search_results(business_id) do
        {:ok, data} -> data
        {:error, _} -> nil
      end

    %{website: website_data, search: search_data}
  end

  @doc """
  Returns true if research data contains website or search results.
  """
  def has_research_data?(%{website: nil, search: nil}), do: false
  def has_research_data?(_), do: true

  @doc """
  Builds the enrichment prompt for a business with research data.
  """
  def build_prompt(business, research_data) do
    reviews_text = extract_reviews_text(business)
    has_reviews = has_reviews?(business)
    category_name = get_category_name(business)
    city_name = get_city_name(business)
    enrichment_hints = get_enrichment_hints(business)
    website_content = format_website_research(research_data.website)
    search_content = format_search_research(research_data.search)
    all_category_slugs = get_all_category_slugs()

    # Get region-specific context (string keys from settings or fallback)
    region = get_region_context(business)
    region_name = region["name"]
    country = region["country"]
    main_lang = region["main_language"]
    local_lang = region["local_language"]
    greeting = region["local_greeting"]
    cultural_examples = Enum.join(region["cultural_examples"] || [], "\n    - ")
    typical_biz = region["typical_business"]

    location = if region_name == country, do: region_name, else: "#{region_name}, #{country}"

    rating_line =
      if business.rating,
        do: "- Rating: #{business.rating}/5 (#{business.review_count || 0} reviews)",
        else: ""

    reviews_section =
      if has_reviews do
        """
        ## CUSTOMER REVIEWS (from Google)
        #{reviews_text}
        """
      else
        """
        ## NO CUSTOMER REVIEWS AVAILABLE
        This business has no Google reviews yet. This is common for many good local businesses.
        IMPORTANT: Do NOT mention the absence of reviews in the description, summary, warnings, or highlights.
        Instead, focus on what you DO know: the business type, location, category, website content, and any other available information.
        Write the description as if you're describing a real place based on what it IS, not what data is missing.
        Leave review_insights as null, sentiment_summary as null, and highlights as an empty array [].
        """
      end

    """
    You are an analyst for a directory helping newcomers INTEGRATE into local life in #{region_name}.

    IMPORTANT PHILOSOPHY:
    We're NOT creating an "expat bubble" service. We help newcomers:
    - Discover authentic local businesses in #{region_name}
    - Learn to navigate services with basic #{main_lang} (most locals are friendly and patient!)
    - Understand and respect local customs and culture
    - Connect WITH locals, not avoid them

    A #{typical_biz} where nobody speaks English but the owner helps you point-and-order
    is MORE valuable than a tourist trap with English menus. We celebrate authenticity.

    ## BUSINESS INFORMATION
    - Name: #{business.name}
    - Category: #{category_name}
    - City: #{city_name}, #{location}
    - Address: #{business.address || "Not provided"}
    - Phone: #{business.phone || "Not provided"}
    - Website: #{business.website || "Not provided"}
    #{rating_line}
    - Place Types: #{get_place_types(business)}

    #{reviews_section}
    #{website_content}
    #{search_content}
    #{enrichment_hints}

    ## ANALYSIS - Provide JSON with these fields:

    ```json
    {
      "description": "2-3 sentences in English. Focus on what makes this place valuable - whether that's professional expertise, authentic local character, or both. Don't mention language barriers as negatives. NEVER mention the absence of reviews or that data is limited - write confidently about what the business IS based on its name, category, location, and any available info.",

      "summary": "One sentence (max 100 chars) capturing the essence. Never reference reviews or lack thereof.",

      "local_gem_score": 0.0-1.0,
      "local_gem_reasoning": "How authentically local is this? Family-run? Traditional? Local clientele?",

      "newcomer_friendly_score": 0.0-1.0,
      "newcomer_friendly_reasoning": "Can someone with basic #{main_lang} and willingness to try manage here? (High score = easy, but doesn't mean it's 'better')",

      "speaks_english": true/false,
      "speaks_english_confidence": 0.0-1.0,
      "languages_spoken": ["#{region["language_code"]}", "en", etc.],

      "languages_taught": ["#{main_lang}"#{if local_lang, do: ", \"#{local_lang}\"", else: ""}, "English", etc.],
      // ONLY for language schools/academies. What languages does this school TEACH?
      // For non-language-school businesses, return an empty array [].

      "integration_tips": [
        "Tip to help newcomers connect with locals",
        "Practical tip that respects local customs"
      ],

      "cultural_notes": [
        "Local cultural context for #{region_name}",
        "Local custom to know"
      ],

      "service_specialties": [
        "Specific expertise or specialty mentioned in reviews"
      ],

      "highlights": [
        "What reviewers consistently praise - leave EMPTY [] if no reviews exist"
      ],

      "warnings": [
        "Practical warnings only (cash only, closed Mondays, etc.) - NOT 'staff don't speak English' and NEVER 'no reviews available' or 'unverified'"
      ],

      "sentiment_summary": "Brief overall sentiment from reviews, or null if no reviews",

      "review_insights": {
        "common_praise": ["Theme 1", "Theme 2"],
        "common_concerns": ["Concern 1 if any - practical issues only"],
        "notable_quotes": ["Best illustrative quote"],
        "reviewer_demographics": "Who reviews this? Locals? Visitors? Mix?"
      },
      // Set review_insights to null if there are no reviews. Do NOT fabricate review data.

      "quality_score": 0.0-1.0,

      "category_fit_score": 0.0-1.0,
      // How well does this business fit the category "#{get_category_name(business)}"?
      // 0.9-1.0: Perfect fit. 0.5-0.8: Reasonable fit. Below 0.5: Wrong category.

      "suggested_category_slug": null or "slug-string"
      // IMPORTANT: If category_fit_score < 0.5, you MUST set this to the best matching slug from: #{all_category_slugs}
      // If category_fit_score >= 0.5, set to null.
      // If no category fits at all, pick the closest match anyway.
    }
    ```

    ## SCORING GUIDELINES

    **local_gem_score** (authenticity):
    - 0.9-1.0: Truly local institution, family-run, mostly local clientele, traditional
    - 0.6-0.8: Local business with good reputation, serves community
    - 0.3-0.5: Professional service, not specifically "local character"
    - 0.0-0.2: Chain/franchise or primarily tourist-oriented

    **newcomer_friendly_score** (accessibility, NOT "better"):
    - 0.9-1.0: Easy for non-#{main_lang} speakers (but might be less authentic!)
    - 0.6-0.8: Manageable with basic #{main_lang} and pointing
    - 0.3-0.5: Helpful to speak decent #{main_lang}
    - 0.0-0.2: Really need good #{main_lang} (but might be an amazing local gem!)

    NOTE: A low newcomer_friendly_score is NOT negative! It means "bring a #{main_lang}-speaking friend" or "great opportunity to practice #{main_lang}" - we frame this positively.

    **integration_tips** should help newcomers CONNECT with locals:
    - "The owner loves talking about local specialties - ask for recommendations"
    - "This is where locals watch football - great way to make friends"
    - "Bring cash and try ordering in #{main_lang} - they appreciate the effort"
    - NOT "they speak English" or "tourist-friendly"

    **cultural_notes** teach local culture in #{region_name}:
    - #{cultural_examples}
    - Try greeting with '#{greeting}'!

    Respond ONLY with valid JSON. No markdown code blocks.
    """
  end

  @doc """
  Parses an LLM response string into enrichment data.
  Returns `{:ok, enriched_attrs}` or `{:error, reason}`.
  """
  def parse_response(response) do
    cleaned =
      response
      |> String.replace(~r/^```json\s*/m, "")
      |> String.replace(~r/\s*```$/m, "")
      |> String.trim()

    case Jason.decode(cleaned) do
      {:ok, data} ->
        enriched = %{
          description: data["description"],
          summary: data["summary"],
          speaks_english: data["speaks_english"],
          speaks_english_confidence: parse_decimal(data["speaks_english_confidence"]),
          languages_spoken: parse_languages(data["languages_spoken"]),
          newcomer_friendly_score: parse_decimal(data["newcomer_friendly_score"]),
          local_gem_score: parse_decimal(data["local_gem_score"]),
          integration_tips: data["integration_tips"] || [],
          cultural_notes: data["cultural_notes"] || [],
          # Keep for backwards compatibility
          expat_friendly_score: parse_decimal(data["newcomer_friendly_score"]),
          expat_tips: data["integration_tips"] || [],
          # Standard fields
          service_specialties: data["service_specialties"] || [],
          languages_taught: data["languages_taught"] || [],
          highlights: data["highlights"] || [],
          warnings: data["warnings"] || [],
          sentiment_summary: data["sentiment_summary"],
          review_insights: data["review_insights"],
          quality_score: parse_decimal(data["quality_score"]),
          category_fit_score: parse_decimal(data["category_fit_score"]),
          suggested_category_slug: data["suggested_category_slug"]
        }

        {:ok, enriched}

      {:error, error} ->
        Logger.error("Failed to parse LLM response: #{inspect(error)}\nResponse: #{cleaned}")
        {:error, :invalid_json}
    end
  end

  # --- Private helpers ---

  defp get_region_context(business) do
    region_slug =
      case business.region do
        %{slug: slug} -> slug
        _ -> "galicia"
      end

    # Try region.settings["enrichment_context"] first, fallback to hardcoded
    case business.region do
      %{settings: %{"enrichment_context" => ctx}} when is_map(ctx) and map_size(ctx) > 0 ->
        ctx

      _ ->
        Map.get(@fallback_context, region_slug, @fallback_context["galicia"])
    end
  end

  defp format_website_research(nil), do: ""

  defp format_website_research(data) do
    pages = data["pages"] || []
    has_english = data["has_english_version"]

    if Enum.empty?(pages) do
      ""
    else
      all_content =
        pages
        |> Enum.map(fn p -> p["content"] || "" end)
        |> Enum.join("\n\n")
        |> String.slice(0, 8000)

      headings =
        pages
        |> Enum.flat_map(fn p -> p["headings"] || [] end)
        |> Enum.uniq()
        |> Enum.take(15)
        |> Enum.join(", ")

      english_note =
        if has_english,
          do: "YES - website has English version available!",
          else: "No English version detected"

      structured_section = format_structured_data(data["structured_data"])
      social_section = format_social_proof(data["social_proof"])

      """

      ## WEBSITE CONTENT (#{length(pages)} pages crawled)
      **English version available**: #{english_note}
      **Key sections/headings**: #{headings}
      #{structured_section}#{social_section}
      ### Website Text:
      #{all_content}
      """
    end
  end

  defp format_structured_data(nil), do: ""
  defp format_structured_data([]), do: ""

  defp format_structured_data(items) do
    formatted =
      items
      |> Enum.map(fn item ->
        fields =
          item
          |> Enum.reject(fn {_k, v} -> is_nil(v) end)
          |> Enum.map(fn {k, v} -> "  #{k}: #{format_schema_value(v)}" end)
          |> Enum.join("\n")

        fields
      end)
      |> Enum.join("\n---\n")

    """

    ### Structured Data (schema.org):
    #{formatted}
    """
  end

  defp format_schema_value(v) when is_binary(v), do: v
  defp format_schema_value(v) when is_number(v), do: to_string(v)
  defp format_schema_value(v) when is_list(v), do: Enum.map_join(v, ", ", &format_schema_value/1)
  defp format_schema_value(v) when is_map(v), do: Jason.encode!(v)
  defp format_schema_value(v), do: inspect(v)

  defp format_social_proof(nil), do: ""

  defp format_social_proof(proof) do
    testimonials = proof["testimonials"] || []
    awards = proof["awards"] || []

    if testimonials == [] and awards == [] do
      ""
    else
      parts = []

      parts =
        if awards != [] do
          parts ++ ["**Awards/Certifications**: #{Enum.join(awards, "; ")}"]
        else
          parts
        end

      parts =
        if testimonials != [] do
          formatted =
            testimonials
            |> Enum.take(3)
            |> Enum.map(&("  > #{String.slice(&1, 0, 200)}"))
            |> Enum.join("\n")

          parts ++ ["**Customer Testimonials**:\n#{formatted}"]
        else
          parts
        end

      """

      ### Social Proof:
      #{Enum.join(parts, "\n")}
      """
    end
  end

  defp format_search_research(nil), do: ""

  defp format_search_research(data) do
    queries = data["queries"] || []

    if Enum.empty?(queries) do
      ""
    else
      results_text =
        queries
        |> Enum.map(fn q ->
          query = q["query"]
          results = q["results"] || []

          results_formatted =
            results
            |> Enum.take(3)
            |> Enum.map(fn r ->
              "- [#{r["title"]}](#{r["url"]}): #{String.slice(r["content"] || "", 0, 200)}..."
            end)
            |> Enum.join("\n")

          """
          **Search: "#{query}"**
          #{results_formatted}
          """
        end)
        |> Enum.join("\n")

      """

      ## EXTERNAL SOURCES (Web Search Results)
      #{results_text}
      """
    end
  end

  defp has_reviews?(business) do
    case business.raw_data do
      %{"reviews_text" => text} when is_binary(text) and text != "" -> true
      %{"reviews" => reviews} when is_list(reviews) and length(reviews) > 0 -> true
      _ -> false
    end
  end

  defp extract_reviews_text(business) do
    case business.raw_data do
      %{"reviews_text" => text} when is_binary(text) and text != "" ->
        text

      %{"reviews" => reviews} when is_list(reviews) and length(reviews) > 0 ->
        reviews
        |> Enum.take(10)
        |> Enum.map(fn r ->
          lang = r["language"] || "unknown"
          author = r["author"] || "Anonymous"
          rating = r["rating"] || "?"
          text = r["text"] || ""
          "[#{lang}] #{author} (#{rating}★): #{text}"
        end)
        |> Enum.join("\n---\n")

      _ ->
        "No reviews available."
    end
  end

  defp get_category_name(business) do
    case business.category do
      %{name: name} -> name
      _ -> "Unknown"
    end
  end

  defp get_city_name(business) do
    case business.city do
      %{name: name} -> name
      _ -> "Unknown"
    end
  end

  defp get_enrichment_hints(business) do
    locale_hints = get_locale_enrichment_hints(business)

    global_hints =
      case business.category do
        %{enrichment_hints: hints} when is_binary(hints) and hints != "" -> hints
        _ -> nil
      end

    category_section =
      case locale_hints || global_hints do
        nil -> ""
        hints ->
          """

          ## CATEGORY-SPECIFIC ANALYSIS INSTRUCTIONS
          #{hints}
          """
      end

    osm_section = format_osm_hints(business)

    category_section <> osm_section
  end

  defp format_osm_hints(business) do
    hints = get_in(business.raw_data, ["extracted_hints"]) || %{}

    if map_size(hints) == 0 do
      ""
    else
      lines =
        Enum.flat_map(hints, fn
          {"cuisine", v} -> ["- Cuisine type: #{v}"]
          {"description", v} -> ["- OSM description: #{v}"]
          {"operator", v} -> ["- Operator/owner: #{v}"]
          {"brand", v} -> ["- Brand/chain: #{v} (likely NOT a local gem)"]
          {"wheelchair", v} -> ["- Wheelchair accessibility: #{v}"]
          {"takeaway", v} -> ["- Takeaway available: #{v}"]
          {"delivery", v} -> ["- Delivery available: #{v}"]
          {"outdoor_seating", v} -> ["- Outdoor seating: #{v}"]
          {"internet_access", v} -> ["- Internet access: #{v}"]
          {"cash_only", true} -> ["- Payment: CASH ONLY (add this to warnings!)"]
          {"diet_options", diets} -> ["- Diet options: #{Enum.join(diets, ", ")}"]
          {"social_media", social} ->
            social
            |> Enum.map(fn {platform, url} -> "- Social media (#{platform}): #{url}" end)
          _ -> []
        end)

      if lines == [] do
        ""
      else
        """

        ## ADDITIONAL BUSINESS DETAILS (from OpenStreetMap)
        #{Enum.join(lines, "\n")}
        """
      end
    end
  end

  defp get_locale_enrichment_hints(business) do
    region_ctx = get_region_context(business)
    locale = region_ctx["language_code"]

    case business.category do
      %{id: category_id} when not is_nil(category_id) ->
        case GaliciaLocal.Directory.CategoryTranslation.get_for_category_locale(
               category_id,
               locale
             ) do
          {:ok, %{enrichment_hints: hints}} when is_binary(hints) and hints != "" -> hints
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp get_all_category_slugs do
    GaliciaLocal.Directory.Category
    |> Ash.read!()
    |> Enum.map(& &1.slug)
    |> Enum.join(", ")
  end

  defp get_place_types(business) do
    case business.raw_data do
      %{"types" => types} when is_list(types) ->
        types |> Enum.take(5) |> Enum.join(", ")

      _ ->
        "Not specified"
    end
  end

  defp parse_decimal(nil), do: nil
  defp parse_decimal(value) when is_float(value), do: Decimal.from_float(value)
  defp parse_decimal(value) when is_integer(value), do: Decimal.new(value)

  defp parse_decimal(value) when is_binary(value) do
    case Float.parse(value) do
      {float, _} -> Decimal.from_float(float)
      :error -> nil
    end
  end

  defp parse_decimal(_), do: nil

  defp parse_languages(nil), do: []

  defp parse_languages(languages) when is_list(languages) do
    languages
    |> Enum.map(&normalize_language/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp parse_languages(_), do: []

  defp normalize_language(lang) when is_binary(lang) do
    case String.downcase(lang) do
      "es" <> _ -> :es
      "en" <> _ -> :en
      "gl" <> _ -> :gl
      "pt" <> _ -> :pt
      "de" <> _ -> :de
      "fr" <> _ -> :fr
      "nl" <> _ -> :nl
      "it" <> _ -> :it
      "spanish" -> :es
      "english" -> :en
      "galician" -> :gl
      "galego" -> :gl
      "portuguese" -> :pt
      "german" -> :de
      "french" -> :fr
      "dutch" -> :nl
      "italian" -> :it
      "italiano" -> :it
      _ -> nil
    end
  end

  defp normalize_language(lang) when is_atom(lang), do: lang
  defp normalize_language(_), do: nil
end
