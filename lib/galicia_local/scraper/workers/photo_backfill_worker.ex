defmodule GaliciaLocal.Scraper.Workers.PhotoBackfillWorker do
  @moduledoc """
  Oban worker to backfill photos for existing businesses using their Google Places ID.
  """

  use Oban.Worker,
    queue: :scraper,
    max_attempts: 3

  require Logger

  alias GaliciaLocal.Directory.Business
  alias GaliciaLocal.Scraper.GooglePlaces

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"business_id" => business_id}}) do
    case Business.get_by_id(business_id) do
      {:ok, business} ->
        place_id = get_in(business.raw_data, ["place_id"])

        cond do
          is_nil(place_id) ->
            Logger.info("No place_id for #{business.name}, skipping photo backfill")
            :ok

          length(business.photo_urls || []) > 0 ->
            Logger.info("#{business.name} already has photos, skipping")
            :ok

          true ->
            fetch_and_store_photos(business, place_id)
        end

      {:error, _} ->
        Logger.warning("Business #{business_id} not found for photo backfill")
        :ok
    end
  end

  defp fetch_and_store_photos(business, place_id) do
    case GooglePlaces.get_place_details(place_id) do
      {:ok, details} ->
        photo_urls = details[:photos] || []

        if length(photo_urls) > 0 do
          case Ash.update(business, %{photo_urls: photo_urls}) do
            {:ok, _} ->
              Logger.info("Added #{length(photo_urls)} photos to #{business.name}")
              :ok

            {:error, error} ->
              Logger.error("Failed to update photos for #{business.name}: #{inspect(error)}")
              {:error, error}
          end
        else
          Logger.info("No photos found for #{business.name}")
          :ok
        end

      {:error, reason} ->
        Logger.error("Failed to fetch details for #{business.name}: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
