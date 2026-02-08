defmodule GaliciaLocal.Workers.OverpassImportWorker do
  @moduledoc """
  Oban worker that imports businesses from OpenStreetMap via Overpass API
  for a single city. Queued from the regions wizard.
  """

  use Oban.Worker,
    queue: :discovery,
    max_attempts: 2,
    unique: [period: 600, fields: [:args, :queue]]

  require Logger

  alias GaliciaLocal.Scraper.Overpass

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"city_id" => city_id, "region_id" => region_id}}) do
    Logger.info("OverpassImport: starting for city #{city_id}")

    case Overpass.import_businesses(city_id, region_id) do
      {:ok, %{created: created, skipped: skipped, failed: failed}} ->
        Logger.info(
          "OverpassImport: city #{city_id} done — #{created} created, #{skipped} skipped, #{failed} failed"
        )

        :ok

      {:error, reason} ->
        Logger.warning("OverpassImport: city #{city_id} failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
