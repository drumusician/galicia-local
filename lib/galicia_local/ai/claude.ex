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
