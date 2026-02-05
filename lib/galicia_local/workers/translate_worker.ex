defmodule GaliciaLocal.Workers.TranslateWorker do
  @moduledoc """
  Oban worker that translates a single entity to a target locale using DeepL.
  Handles businesses, categories, and cities.
  """

  use Oban.Worker,
    queue: :translations,
    max_attempts: 3,
    unique: [period: 300, fields: [:args, :queue]]

  require Logger

  alias GaliciaLocal.AI.DeepL
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
          case DeepL.translate(city.description, locale, source_lang: "en") do
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

  defp translate_fields(fields, locale) do
    # Separate string fields and array fields
    {string_fields, array_fields} =
      Enum.split_with(fields, fn {_k, v} -> is_binary(v) end)

    # Translate all strings in a single batch call
    string_keys = Enum.map(string_fields, fn {k, _v} -> k end)
    string_values = Enum.map(string_fields, fn {_k, v} -> v end)

    # Flatten array fields into a single batch too
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

          # Rebuild string results
          string_result =
            Enum.zip(string_keys, translated_strings)
            |> Map.new()

          # Rebuild array results
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
