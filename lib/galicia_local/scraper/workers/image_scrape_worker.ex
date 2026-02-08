defmodule GaliciaLocal.Scraper.Workers.ImageScrapeWorker do
  @moduledoc """
  Oban worker that scrapes images from a business website and stores them in photo_urls.

  Only processes businesses that have a website but no existing photos.
  Extracts og:image, twitter:image, and content images from the page.
  """

  use Oban.Worker,
    queue: :scraper,
    max_attempts: 2,
    unique: [period: 3600, fields: [:args, :queue]]

  require Logger

  alias GaliciaLocal.Directory.Business
  alias GaliciaLocal.Scraper.ImageExtractor

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"business_id" => business_id}}) do
    case Business.get_by_id(business_id) do
      {:ok, business} ->
        cond do
          is_nil(business.website) or business.website == "" ->
            Logger.info("ImageScrape: #{business.name} has no website, skipping")
            :ok

          length(business.photo_urls || []) > 0 ->
            Logger.info("ImageScrape: #{business.name} already has photos, skipping")
            :ok

          true ->
            scrape_and_store(business)
        end

      {:error, _} ->
        Logger.warning("ImageScrape: business #{business_id} not found")
        :ok
    end
  end

  defp scrape_and_store(business) do
    Logger.info("ImageScrape: fetching images from #{business.website} for #{business.name}")

    case ImageExtractor.extract_images(business.website) do
      {:ok, []} ->
        Logger.info("ImageScrape: no images found on #{business.website}")
        :ok

      {:ok, urls} ->
        case Ash.update(business, %{photo_urls: urls}, action: :update) do
          {:ok, _} ->
            Logger.info("ImageScrape: added #{length(urls)} images to #{business.name}")
            :ok

          {:error, error} ->
            Logger.error(
              "ImageScrape: failed to update #{business.name}: #{inspect(error)}"
            )

            {:error, error}
        end

      {:error, reason} ->
        Logger.warning(
          "ImageScrape: failed to fetch #{business.website}: #{inspect(reason)}"
        )

        # Don't retry for permanent failures
        case reason do
          {:http_error, status} when status in [403, 404, 410, 451] -> :ok
          :not_html -> :ok
          %Req.TransportError{} -> :ok
          %Mint.TransportError{} -> :ok
          _ -> {:error, reason}
        end
    end
  end

  @doc """
  Queue image scraping for all businesses that have a website but no photos.
  Returns `{:ok, %{queued: n}}`.
  """
  def queue_all_missing do
    queue_missing(nil)
  end

  @doc """
  Queue image scraping for businesses in a specific region that have a website but no photos.
  Returns `{:ok, %{queued: n}}`.
  """
  def queue_missing(region_id) do
    import Ecto.Query

    query =
      GaliciaLocal.Directory.Business
      |> Ash.Query.new()
      |> Ash.Query.data_layer_query()
      |> case do
        {:ok, ecto_query} -> ecto_query
        _ -> raise "Failed to build query"
      end

    query =
      query
      |> where([b], not is_nil(b.website) and b.website != "")
      |> where([b], is_nil(b.photo_urls) or b.photo_urls == ^[])

    query =
      if region_id do
        where(query, [b], b.region_id == ^region_id)
      else
        query
      end

    query = select(query, [b], b.id)

    business_ids = GaliciaLocal.Repo.all(query)

    jobs =
      business_ids
      |> Enum.map(fn id ->
        %{business_id: id}
        |> __MODULE__.new()
        |> Oban.insert()
      end)

    queued = Enum.count(jobs, &match?({:ok, _}, &1))
    Logger.info("ImageScrape: queued #{queued} jobs")

    {:ok, %{queued: queued}}
  end
end
