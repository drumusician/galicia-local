defmodule GaliciaLocal.Workers.TranslateWorker do
  @moduledoc """
  Oban worker that translates a single entity to a target locale.

  Uses Claude CLI when ENABLE_CLI_ENRICHMENT is set (free via Max plan),
  falls back to DeepL API otherwise.
  """

  use Oban.Worker,
    queue: :translations,
    max_attempts: 3,
    unique: [period: 300, fields: [:args, :queue]]

  require Logger

  alias GaliciaLocal.AI.DeepL
  alias GaliciaLocal.AI.ClaudeCLI
  alias GaliciaLocal.Directory.{Business, BusinessTranslation, Category, CategoryTranslation, City, CityTranslation}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"type" => type, "id" => id, "target_locale" => locale}}) do
    Logger.info("TranslateWorker: translating #{type} #{id} to #{locale}")

    case type do
      "business" -> translate_business(id, locale)
      "category" -> translate_category(id, locale)
      "city" -> translate_city(id, locale)
      _ -> {:error, "Unknown type: #{type}"}
    end
  end

  defp translate_business(id, locale) do
    case Business.get_by_id(id) do
      {:ok, business} ->
        fields = collect_business_fields(business)

        if Enum.empty?(fields) do
          Logger.info("TranslateWorker: business #{id} has no content to translate")
          :ok
        else
          case translate_fields(fields, locale) do
            {:ok, translated} ->
              BusinessTranslation.upsert(%{
                business_id: business.id,
                locale: locale,
                description: translated[:description],
                summary: translated[:summary],
                highlights: translated[:highlights] || [],
                warnings: translated[:warnings] || [],
                integration_tips: translated[:integration_tips] || [],
                cultural_notes: translated[:cultural_notes] || [],
                content_source: "ai_generated",
                source_locale: "en"
              })

              Logger.info("TranslateWorker: translated business #{id} to #{locale}")
              :ok

            {:error, reason} ->
              {:error, reason}
          end
        end

      {:error, _} ->
        Logger.warning("TranslateWorker: business #{id} not found")
        :ok
    end
  end

  defp translate_category(id, locale) do
    case Category.get_by_id(id) do
      {:ok, category} ->
        fields = %{}
        fields = if non_empty?(category.name), do: Map.put(fields, :name, category.name), else: fields
        fields = if non_empty?(category.description), do: Map.put(fields, :description, category.description), else: fields

        if Enum.empty?(fields) do
          :ok
        else
          case translate_fields(fields, locale) do
            {:ok, translated} ->
              CategoryTranslation.upsert(%{
                category_id: category.id,
                locale: locale,
                name: translated[:name],
                description: translated[:description]
              })

              Logger.info("TranslateWorker: translated category #{id} to #{locale}")
              :ok

            {:error, reason} ->
              {:error, reason}
          end
        end

      {:error, _} ->
        :ok
    end
  end

  defp translate_city(id, locale) do
    case City.get_by_id(id) do
      {:ok, city} ->
        if non_empty?(city.description) do
          case translate_text(city.description, locale) do
            {:ok, translated} ->
              CityTranslation.upsert(%{
                city_id: city.id,
                locale: locale,
                description: translated
              })

              Logger.info("TranslateWorker: translated city #{id} to #{locale}")
              :ok

            {:error, reason} ->
              {:error, reason}
          end
        else
          :ok
        end

      {:error, _} ->
        :ok
    end
  end

  defp collect_business_fields(business) do
    fields = %{}
    fields = if non_empty?(business.description), do: Map.put(fields, :description, business.description), else: fields
    fields = if non_empty?(business.summary), do: Map.put(fields, :summary, business.summary), else: fields
    fields = if non_empty_list?(business.highlights), do: Map.put(fields, :highlights, business.highlights), else: fields
    fields = if non_empty_list?(business.warnings), do: Map.put(fields, :warnings, business.warnings), else: fields
    fields = if non_empty_list?(business.integration_tips), do: Map.put(fields, :integration_tips, business.integration_tips), else: fields
    fields = if non_empty_list?(business.cultural_notes), do: Map.put(fields, :cultural_notes, business.cultural_notes), else: fields
    fields
  end

  # --- Translation dispatch ---

  defp use_claude_cli? do
    System.get_env("ENABLE_CLI_ENRICHMENT") in ["true", "1"] and ClaudeCLI.cli_available?()
  end

  defp translate_text(text, locale) do
    if use_claude_cli?() do
      translate_text_with_claude(text, locale)
    else
      DeepL.translate(text, locale, source_lang: "en")
    end
  end

  defp translate_fields(fields, locale) do
    if use_claude_cli?() do
      translate_fields_with_claude(fields, locale)
    else
      translate_fields_with_deepl(fields, locale)
    end
  end

  # --- Claude CLI translation ---

  defp translate_text_with_claude(text, locale) do
    prompt = build_claude_prompt(%{text: text}, locale)

    case ClaudeCLI.complete(prompt) do
      {:ok, response} ->
        case extract_claude_json(response) do
          {:ok, %{"text" => translated}} -> {:ok, translated}
          {:ok, _} -> {:error, :unexpected_claude_response}
          error -> error
        end

      {:error, _} = error ->
        error
    end
  end

  defp translate_fields_with_claude(fields, locale) do
    prompt = build_claude_prompt(fields, locale)

    case ClaudeCLI.complete(prompt) do
      {:ok, response} ->
        case extract_claude_json(response) do
          {:ok, translated} when is_map(translated) ->
            result =
              Enum.reduce(fields, %{}, fn {key, _value}, acc ->
                key_str = to_string(key)

                case Map.get(translated, key_str) do
                  nil -> acc
                  val -> Map.put(acc, key, val)
                end
              end)

            {:ok, result}

          {:ok, _} ->
            {:error, :unexpected_claude_response}

          error ->
            error
        end

      {:error, _} = error ->
        error
    end
  end

  defp build_claude_prompt(fields, locale) do
    locale_name = locale_display_name(locale)

    json_input = Jason.encode!(fields, pretty: false)

    """
    Translate the following JSON values from English to #{locale_name} (#{locale}).
    Keep the JSON keys exactly the same, only translate the string values.
    Arrays should have the same number of elements, each translated.
    Return ONLY valid JSON, no markdown, no explanation.

    #{json_input}
    """
  end

  defp locale_display_name("es"), do: "Spanish"
  defp locale_display_name("nl"), do: "Dutch"
  defp locale_display_name("de"), do: "German"
  defp locale_display_name("fr"), do: "French"
  defp locale_display_name("pt"), do: "Portuguese"
  defp locale_display_name(locale), do: locale

  defp extract_claude_json(text) do
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

  # --- DeepL translation (fallback) ---

  defp translate_fields_with_deepl(fields, locale) do
    {string_fields, array_fields} =
      Enum.split_with(fields, fn {_k, v} -> is_binary(v) end)

    string_keys = Enum.map(string_fields, fn {k, _v} -> k end)
    string_values = Enum.map(string_fields, fn {_k, v} -> v end)

    array_meta =
      Enum.map(array_fields, fn {k, list} -> {k, length(list)} end)

    array_values = Enum.flat_map(array_fields, fn {_k, list} -> list end)

    all_texts = string_values ++ array_values

    if Enum.empty?(all_texts) do
      {:ok, %{}}
    else
      case DeepL.translate_batch(all_texts, locale, source_lang: "en") do
        {:ok, translated_all} ->
          {translated_strings, translated_arrays_flat} = Enum.split(translated_all, length(string_values))

          string_result =
            Enum.zip(string_keys, translated_strings)
            |> Map.new()

          {array_result, _rest} =
            Enum.reduce(array_meta, {%{}, translated_arrays_flat}, fn {key, count}, {acc, remaining} ->
              {items, rest} = Enum.split(remaining, count)
              {Map.put(acc, key, items), rest}
            end)

          {:ok, Map.merge(string_result, array_result)}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp non_empty?(nil), do: false
  defp non_empty?(""), do: false
  defp non_empty?(_), do: true

  defp non_empty_list?(nil), do: false
  defp non_empty_list?([]), do: false
  defp non_empty_list?(_), do: true
end
