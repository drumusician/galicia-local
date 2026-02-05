defmodule GaliciaLocal.Directory.Business.Changes.TranslateToSpanish do
  @moduledoc """
  Ash change that translates enriched English content to Spanish using DeepL.

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

  alias GaliciaLocal.AI.DeepL

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
    # Separate string and array fields
    {string_fields, array_fields} =
      Enum.split_with(fields, fn field ->
        is_binary(Map.get(business, field))
      end)

    string_values = Enum.map(string_fields, fn f -> Map.get(business, f) end)
    array_meta = Enum.map(array_fields, fn f -> {f, length(Map.get(business, f, []))} end)
    array_values = Enum.flat_map(array_fields, fn f -> Map.get(business, f, []) end)

    all_texts = string_values ++ array_values

    if Enum.empty?(all_texts) do
      {:ok, %{}}
    else
      case DeepL.translate_batch(all_texts, "es", source_lang: "en") do
        {:ok, translated_all} ->
          {translated_strings, translated_arrays_flat} =
            Enum.split(translated_all, length(string_values))

          # Build _es string fields
          string_result =
            Enum.zip(string_fields, translated_strings)
            |> Enum.map(fn {field, text} -> {:"#{field}_es", text} end)
            |> Map.new()

          # Build _es array fields
          {array_result, _rest} =
            Enum.reduce(array_meta, {%{}, translated_arrays_flat}, fn {field, count}, {acc, remaining} ->
              {items, rest} = Enum.split(remaining, count)
              {Map.put(acc, :"#{field}_es", items), rest}
            end)

          {:ok, Map.merge(string_result, array_result)}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end
end
