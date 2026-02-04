defmodule GaliciaLocalWeb.LocaleContent do
  @moduledoc """
  Helper for displaying locale-aware dynamic content.

  Supports three approaches (checked in order):
  1. Translation table: If record has `translations` loaded, uses translation for locale
  2. Legacy _es fields: Falls back to _es suffixed fields for Spanish
  3. Default field: Returns the English/default field value

  For best performance, pre-load translations with: `Ash.load!(record, :translations)`
  """

  @doc """
  Returns the localized value for a field.

  Checks in order:
  1. Translation table (if loaded)
  2. Legacy _es field (for Spanish)
  3. Default field value

  ## Examples

      localized(business, :description, "es")
      localized(business, :summary, "nl")
      localized(city, :description, "en")
  """
  def localized(record, field, locale) do
    # First, try translation table if loaded
    case get_from_translations(record, field, locale) do
      {:ok, value} -> value
      :not_found ->
        # Fall back to legacy _es field for Spanish
        if locale == "es" do
          get_legacy_es_field(record, field)
        else
          # For English or unsupported locales, return default field
          Map.get(record, field)
        end
    end
  end

  @doc """
  Returns the localized name for a category.
  Checks translation table first, then falls back to name_es for Spanish.
  """
  def localized_name(record, locale) do
    # Try translation table first
    case get_from_translations(record, :name, locale) do
      {:ok, value} -> value
      :not_found ->
        # Fall back to legacy name_es for Spanish
        if locale == "es" do
          case Map.get(record, :name_es) do
            nil -> Map.get(record, :name)
            "" -> Map.get(record, :name)
            value -> value
          end
        else
          Map.get(record, :name)
        end
    end
  end

  # Private helpers

  defp get_from_translations(record, field, locale) do
    case Map.get(record, :translations) do
      %Ash.NotLoaded{} -> :not_found
      nil -> :not_found
      [] -> :not_found
      translations when is_list(translations) ->
        case Enum.find(translations, &(&1.locale == locale)) do
          nil -> :not_found
          translation ->
            case Map.get(translation, field) do
              nil -> :not_found
              "" -> :not_found
              [] -> :not_found
              value -> {:ok, value}
            end
        end
    end
  end

  defp get_legacy_es_field(record, field) do
    es_field = :"#{field}_es"

    if Map.has_key?(record, es_field) do
      case Map.get(record, es_field) do
        nil -> Map.get(record, field)
        "" -> Map.get(record, field)
        [] -> Map.get(record, field)
        value -> value
      end
    else
      Map.get(record, field)
    end
  end
end
