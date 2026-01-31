defmodule GaliciaLocalWeb.LocaleContent do
  @moduledoc """
  Helper for displaying locale-aware dynamic content.
  Falls back to the default (English) field when no translation exists.
  """

  @doc """
  Returns the Spanish version of a field if the locale is "es" and the value exists,
  otherwise returns the default field value.

      localized(business, :description, "es")
      # => business.description_es || business.description
  """
  def localized(record, field, locale) when locale == "es" do
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

  def localized(record, field, _locale) do
    Map.get(record, field)
  end

  @doc """
  Returns the localized name for a category.
  """
  def localized_name(record, locale) when locale == "es" do
    case Map.get(record, :name_es) do
      nil -> Map.get(record, :name)
      "" -> Map.get(record, :name)
      value -> value
    end
  end

  def localized_name(record, _locale), do: Map.get(record, :name)
end
