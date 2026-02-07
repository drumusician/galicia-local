defmodule GaliciaLocal.Directory.Business.Changes.TranslateAllLocales do
  @moduledoc """
  Ash change that queues translation jobs for all region locales.

  Loads the business's region to determine `supported_locales`, then queues
  a `TranslateWorker` job for each non-English locale that's missing a translation.
  """
  use Ash.Resource.Change

  require Logger

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, business ->
      case queue_translations(business) do
        {:ok, count} ->
          if count > 0 do
            Logger.info("Queued #{count} translation jobs for business #{business.id}")
          end

          {:ok, business}

        {:error, reason} ->
          Logger.error(
            "Failed to queue translations for business #{business.id}: #{inspect(reason)}"
          )

          {:ok, business}
      end
    end)
  end

  defp queue_translations(business) do
    business =
      case Ash.load(business, :region) do
        {:ok, loaded} -> loaded
        _ -> business
      end

    target_locales = get_target_locales(business)
    existing_locales = get_existing_translation_locales(business.id)
    missing_locales = target_locales -- existing_locales

    jobs =
      Enum.map(missing_locales, fn locale ->
        GaliciaLocal.Workers.TranslateWorker.new(%{
          type: "business",
          id: business.id,
          target_locale: locale
        })
      end)

    case Oban.insert_all(jobs) do
      inserted when is_list(inserted) -> {:ok, length(inserted)}
      error -> {:error, error}
    end
  end

  defp get_target_locales(business) do
    case business.region do
      %{supported_locales: locales} when is_list(locales) ->
        Enum.reject(locales, &(&1 == "en"))

      _ ->
        []
    end
  end

  defp get_existing_translation_locales(business_id) do
    case GaliciaLocal.Directory.BusinessTranslation.get_for_business(business_id) do
      {:ok, translations} ->
        translations
        |> Enum.filter(fn t -> t.description != nil and t.description != "" end)
        |> Enum.map(& &1.locale)

      _ ->
        []
    end
  end
end
