defmodule GaliciaLocal.Scraper.CrawlResume do
  @moduledoc """
  Detects incomplete crawls on startup and resumes processing.
  Runs once as a Task in the supervision tree.
  """
  use Task, restart: :temporary
  require Logger

  alias GaliciaLocal.Directory.DiscoveryCrawl

  def start_link(_opts) do
    Task.start_link(__MODULE__, :run, [])
  end

  def run do
    # Wait for Repo and Oban to be ready
    Process.sleep(:timer.seconds(5))

    case DiscoveryCrawl.find_incomplete() do
      {:ok, incomplete} when incomplete != [] ->
        Logger.info("CrawlResume: found #{length(incomplete)} incomplete crawls")
        Enum.each(incomplete, &resume/1)

      _ ->
        :ok
    end
  end

  defp resume(crawl) do
    crawl_id = crawl.crawl_id
    pages = count_pages_on_disk(crawl_id)

    case crawl.status do
      :crawling ->
        if pages > 0 do
          Logger.info("CrawlResume: #{crawl_id} was crawling with #{pages} pages, marking crawled")
          DiscoveryCrawl.mark_crawled(crawl, pages)
          enqueue_processing(crawl_id)
        else
          Logger.info("CrawlResume: #{crawl_id} was crawling with 0 pages, marking failed")
          DiscoveryCrawl.mark_failed(crawl, "Spider interrupted with no pages")
        end

      :crawled ->
        Logger.info("CrawlResume: #{crawl_id} was crawled but not processed, enqueueing")
        enqueue_processing(crawl_id)

      :processing ->
        Logger.info("CrawlResume: #{crawl_id} was mid-processing, re-enqueueing")
        DiscoveryCrawl.mark_crawled(crawl, pages)
        enqueue_processing(crawl_id)

      _ ->
        :ok
    end
  end

  defp enqueue_processing(crawl_id) do
    %{crawl_id: crawl_id}
    |> GaliciaLocal.Workers.DiscoveryProcessWorker.new(
      scheduled_at: DateTime.add(DateTime.utc_now(), 30, :second)
    )
    |> Oban.insert()
  end

  defp count_pages_on_disk(crawl_id) do
    dir = Path.join(GaliciaLocal.Scraper.discovery_data_dir(), crawl_id)

    case File.ls(dir) do
      {:ok, files} -> Enum.count(files, &String.starts_with?(&1, "page_"))
      {:error, _} -> 0
    end
  end
end
