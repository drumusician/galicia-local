defmodule GaliciaLocal.AI.Claude do
  @moduledoc """
  Client for interacting with Claude API for LLM-based data enrichment.
  """
  require Logger

  @api_url "https://api.anthropic.com/v1/messages"
  @model "claude-sonnet-4-20250514"
  @max_tokens 1024

  @doc """
  Send a completion request to Claude.
  Returns {:ok, response_text} or {:error, reason}
  """
  def complete(prompt, opts \\ []) do
    api_key = get_api_key()

    if is_nil(api_key) or api_key == "" do
      Logger.warning("No ANTHROPIC_API_KEY configured, using mock response")
      {:ok, mock_response()}
    else
      do_request(prompt, api_key, opts)
    end
  end

  defp do_request(prompt, api_key, opts) do
    model = Keyword.get(opts, :model, @model)
    max_tokens = Keyword.get(opts, :max_tokens, @max_tokens)

    body = %{
      model: model,
      max_tokens: max_tokens,
      messages: [
        %{role: "user", content: prompt}
      ]
    }

    headers = [
      {"x-api-key", api_key},
      {"anthropic-version", "2023-06-01"},
      {"content-type", "application/json"}
    ]

    case Req.post(@api_url, json: body, headers: headers, receive_timeout: 60_000) do
      {:ok, %{status: 200, body: response_body}} ->
        extract_content(response_body)

      {:ok, %{status: status, body: body}} ->
        Logger.error("Claude API error: status=#{status}, body=#{inspect(body)}")
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        Logger.error("Claude API request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp extract_content(%{"content" => [%{"text" => text} | _]}) do
    {:ok, String.trim(text)}
  end

  defp extract_content(response) do
    Logger.error("Unexpected Claude response format: #{inspect(response)}")
    {:error, :unexpected_response}
  end

  @doc """
  Generate English and Spanish descriptions for a city.
  Returns {:ok, %{description: "...", description_es: "..."}} or {:error, reason}
  """
  def generate_city_descriptions(city_name, province) do
    prompt = """
    Write two brief descriptions (2-3 sentences each) for the city of #{city_name} in #{province}, Galicia, Spain.
    These are for an expat guide website helping foreigners settle in Galicia.

    Focus on: what makes the city interesting, quality of life, notable features, and relevance to expats.

    Also include the approximate population of the city (most recent available data).

    Respond ONLY with valid JSON in this exact format:
    {"description": "English description here", "description_es": "Spanish description here", "population": 12345}
    """

    case complete(prompt, max_tokens: 512) do
      {:ok, text} ->
        case Jason.decode(text) do
          {:ok, %{"description" => desc, "description_es" => desc_es} = parsed} ->
            result = %{description: desc, description_es: desc_es}
            result = if parsed["population"], do: Map.put(result, :population, parsed["population"]), else: result
            {:ok, result}

          _ ->
            Logger.error("Failed to parse city descriptions JSON: #{text}")
            {:error, :parse_error}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_api_key do
    System.get_env("ANTHROPIC_API_KEY")
  end

  defp mock_response do
    """
    {
      "description": "A local business in Galicia offering quality services to the community.",
      "summary": "Friendly local establishment with good reviews",
      "speaks_english": false,
      "speaks_english_confidence": 0.3,
      "languages_spoken": ["es", "gl"],
      "highlights": ["Friendly staff", "Good location"],
      "warnings": [],
      "quality_score": 0.5
    }
    """
  end
end
