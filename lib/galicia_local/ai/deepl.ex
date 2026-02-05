defmodule GaliciaLocal.AI.DeepL do
  @moduledoc """
  Client for DeepL translation API.
  Used for translating existing content between languages.
  For content generation/enrichment, use `GaliciaLocal.AI.Claude` instead.
  """
  require Logger

  @api_url "https://api.deepl.com/v2/translate"

  @locale_to_deepl %{
    "en" => "EN",
    "es" => "ES",
    "nl" => "NL",
    "de" => "DE",
    "fr" => "FR",
    "pt" => "PT-PT"
  }

  @doc """
  Translate a single text string to the target locale.
  Returns `{:ok, translated_text}` or `{:error, reason}`.

  Options:
    - `:source_lang` - source language code (default: auto-detect)
    - `:formality` - "more", "less", or "default" (default: "default")
  """
  def translate(text, target_locale, opts \\ []) do
    case translate_batch([text], target_locale, opts) do
      {:ok, [translated]} -> {:ok, translated}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Translate multiple texts in a single API call.
  Returns `{:ok, [translated_texts]}` or `{:error, reason}`.
  Texts are returned in the same order as provided.

  Options:
    - `:source_lang` - source language code (default: auto-detect)
    - `:formality` - "more", "less", or "default" (default: "default")
  """
  def translate_batch(texts, target_locale, opts \\ []) do
    api_key = get_api_key()

    if is_nil(api_key) or api_key == "" do
      Logger.warning("No DEEPL_API_KEY configured, returning original texts")
      {:ok, texts}
    else
      do_translate(texts, target_locale, api_key, opts)
    end
  end

  defp do_translate(texts, target_locale, api_key, opts) do
    target_lang = Map.get(@locale_to_deepl, target_locale, String.upcase(target_locale))

    body =
      %{text: texts, target_lang: target_lang}
      |> maybe_add_source_lang(opts)
      |> maybe_add_formality(opts)

    headers = [
      {"authorization", "DeepL-Auth-Key #{api_key}"},
      {"content-type", "application/json"}
    ]

    case Req.post(@api_url, json: body, headers: headers, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: %{"translations" => translations}}} ->
        translated = Enum.map(translations, & &1["text"])
        {:ok, translated}

      {:ok, %{status: status, body: response_body}} ->
        Logger.error("DeepL API error: status=#{status}, body=#{inspect(response_body)}")
        {:error, {:api_error, status, response_body}}

      {:error, reason} ->
        Logger.error("DeepL API request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp maybe_add_source_lang(body, opts) do
    case Keyword.get(opts, :source_lang) do
      nil -> body
      lang -> Map.put(body, :source_lang, Map.get(@locale_to_deepl, lang, String.upcase(lang)))
    end
  end

  defp maybe_add_formality(body, opts) do
    case Keyword.get(opts, :formality) do
      nil -> body
      formality -> Map.put(body, :formality, formality)
    end
  end

  defp get_api_key do
    System.get_env("DEEPL_API_KEY")
  end
end
