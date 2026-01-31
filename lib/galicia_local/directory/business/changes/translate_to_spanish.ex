defmodule GaliciaLocal.Directory.Business.Changes.TranslateToSpanish do
  @moduledoc """
  Ash change that translates enriched English content to Spanish using Claude LLM.

  Translates the following fields when Spanish versions are missing:
  - summary → summary_es
  - highlights → highlights_es
  - warnings → warnings_es
  - integration_tips → integration_tips_es
  - cultural_notes → cultural_notes_es

  Skips fields that already have Spanish content, or where the English source is empty.
  """
  use Ash.Resource.Change

  require Logger

  @translatable_fields ~w(summary highlights warnings integration_tips cultural_notes)a

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      business = changeset.data

      fields_to_translate = fields_needing_translation(business)

      if Enum.empty?(fields_to_translate) do
        Logger.info("Business #{business.id}: no fields need Spanish translation")
        changeset
      else
        case translate_fields(business, fields_to_translate) do
          {:ok, translations} ->
            Ash.Changeset.force_change_attributes(changeset, translations)

          {:error, reason} ->
            Logger.error("Failed to translate business #{business.id}: #{inspect(reason)}")
            changeset
        end
      end
    end)
  end

  defp fields_needing_translation(business) do
    Enum.filter(@translatable_fields, fn field ->
      english_value = Map.get(business, field)
      spanish_field = :"#{field}_es"
      spanish_value = Map.get(business, spanish_field)

      has_english = not empty?(english_value)
      missing_spanish = empty?(spanish_value)

      has_english and missing_spanish
    end)
  end

  defp empty?(nil), do: true
  defp empty?(""), do: true
  defp empty?([]), do: true
  defp empty?(_), do: false

  defp translate_fields(business, fields) do
    content_to_translate =
      Enum.map(fields, fn field ->
        value = Map.get(business, field)
        {field, value}
      end)

    prompt = build_translation_prompt(business.name, content_to_translate)

    case GaliciaLocal.AI.Claude.complete(prompt, max_tokens: 2048, model: "claude-sonnet-4-20250514") do
      {:ok, response} ->
        parse_translation_response(response, fields)

      {:error, _} = error ->
        error
    end
  end

  defp build_translation_prompt(business_name, content) do
    fields_json =
      content
      |> Enum.map(fn {field, value} ->
        json_value = if is_list(value), do: Jason.encode!(value), else: Jason.encode!(value)
        ~s("#{field}": #{json_value})
      end)
      |> Enum.join(",\n  ")

    """
    Translate the following business content from English to Spanish.
    This is for "#{business_name}", a business listing in Galicia, Spain.

    IMPORTANT GUIDELINES:
    - Use natural, conversational Spanish (Castilian, as used in Galicia)
    - Keep the same tone and style as the original
    - For arrays, translate each element individually, maintaining the same number of items
    - For strings, provide a direct translation
    - Preserve any specific names, addresses, or technical terms

    Content to translate:
    {
      #{fields_json}
    }

    Respond ONLY with valid JSON containing the translated fields with "_es" suffix:
    For example: {"summary_es": "...", "highlights_es": ["...", "..."]}

    Respond ONLY with valid JSON. No markdown code blocks.
    """
  end

  defp parse_translation_response(response, expected_fields) do
    cleaned =
      response
      |> String.replace(~r/^```json\s*/m, "")
      |> String.replace(~r/\s*```$/m, "")
      |> String.trim()

    case Jason.decode(cleaned) do
      {:ok, data} ->
        translations =
          expected_fields
          |> Enum.reduce(%{}, fn field, acc ->
            es_key = "#{field}_es"
            es_atom = :"#{field}_es"

            case Map.get(data, es_key) do
              nil -> acc
              value -> Map.put(acc, es_atom, value)
            end
          end)

        {:ok, translations}

      {:error, error} ->
        Logger.error("Failed to parse translation response: #{inspect(error)}\nResponse: #{cleaned}")
        {:error, :invalid_json}
    end
  end
end
