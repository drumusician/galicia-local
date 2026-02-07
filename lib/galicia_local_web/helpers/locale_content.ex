defmodule GaliciaLocalWeb.LocaleContent do
  @moduledoc """
  Helper for displaying locale-aware dynamic content.

  Checks the translation table first, then falls back to the default (English) field value.
  For best performance, pre-load translations with: `Ash.load!(record, :translations)`
  """

  @doc """
  Returns the localized value for a field.

  Checks in order:
  1. Translation table (if loaded)
  2. Default field value

  ## Examples

      localized(business, :description, "es")
      localized(business, :summary, "nl")
      localized(city, :description, "en")
  """
  def localized(record, field, locale) do
    case get_from_translations(record, field, locale) do
      {:ok, value} -> value
      :not_found -> Map.get(record, field)
    end
  end

  @doc """
  Returns the localized name for a record (category, etc.).
  Checks translation table first, then falls back to the default name.
  """
  def localized_name(record, locale) do
    case get_from_translations(record, :name, locale) do
      {:ok, value} -> value
      :not_found -> Map.get(record, :name)
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
end
