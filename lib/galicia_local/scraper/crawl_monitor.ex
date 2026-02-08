defmodule GaliciaLocal.Scraper.CrawlMonitor do
  @moduledoc """
  Monitors active Crawly discovery spiders and updates the DiscoveryCrawl
  record when they finish. Polls since Crawly has no completion callback.
  """
  use GenServer
  require Logger

  alias GaliciaLocal.Directory.DiscoveryCrawl
  alias GaliciaLocal.Scraper.Spiders.DiscoverySpider

  @poll_interval :timer.seconds(5)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Start watching a crawl_id for spider completion"
  def watch(crawl_id) do
    GenServer.cast(__MODULE__, {:watch, crawl_id})
  end

  @impl true
  def init(_opts) do
    {:ok, %{watching: MapSet.new()}}
  end

  @impl true
  def handle_cast({:watch, crawl_id}, state) do
    if MapSet.size(state.watching) == 0 do
      Process.send_after(self(), :poll, @poll_interval)
    end

    {:noreply, %{state | watching: MapSet.put(state.watching, crawl_id)}}
  end

  @impl true
  def handle_info(:poll, state) do
    if MapSet.size(state.watching) == 0 do
      {:noreply, state}
    else
      spider_running? =
        case Crawly.Engine.running_spiders() do
          spiders when is_map(spiders) -> Map.has_key?(spiders, DiscoverySpider)
          _ -> false
        end

      new_watching =
        if spider_running? do
          # Still running — update page counts from disk
          Enum.each(state.watching, fn crawl_id ->
            pages = count_pages_on_disk(crawl_id)

            case DiscoveryCrawl.get_by_crawl_id(crawl_id) do
              {:ok, crawl} when crawl.pages_crawled != pages ->
                DiscoveryCrawl.update_pages_crawled(crawl, pages)

              _ ->
                :ok
            end
          end)

          state.watching
        else
          Enum.each(state.watching, fn crawl_id ->
            pages = count_pages_on_disk(crawl_id)

            case DiscoveryCrawl.get_by_crawl_id(crawl_id) do
              {:ok, crawl} ->
                Logger.info("CrawlMonitor: spider finished for #{crawl_id}, #{pages} pages")
                DiscoveryCrawl.mark_crawled(crawl, pages)

              _ ->
                Logger.warning("CrawlMonitor: no DB record for crawl #{crawl_id}")
            end
          end)

          MapSet.new()
        end

      if MapSet.size(new_watching) > 0 do
        Process.send_after(self(), :poll, @poll_interval)
      end

      {:noreply, %{state | watching: new_watching}}
    end
  end

  defp count_pages_on_disk(crawl_id) do
    dir = Path.join(GaliciaLocal.Scraper.discovery_data_dir(), crawl_id)

    case File.ls(dir) do
      {:ok, files} -> Enum.count(files, &String.starts_with?(&1, "page_"))
      {:error, _} -> 0
    end
  end
end
