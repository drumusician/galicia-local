defmodule GaliciaLocal.Scraper.Pipelines.SaveToFile do
  @moduledoc """
  Crawly pipeline that saves scraped page items to JSON files on disk.
  Used by the DiscoverySpider to save raw page content for later
  processing by Claude Code.
  """

  require Logger

  @behaviour Crawly.Pipeline

  @impl Crawly.Pipeline
  def run(item, state) do
    crawl_id = item[:crawl_id] || "unknown"
    dir = Path.join(GaliciaLocal.Scraper.discovery_data_dir(), crawl_id)
    File.mkdir_p!(dir)

    # Get and increment page counter
    counter = Map.get(state, :page_counter, 0) + 1
    state = Map.put(state, :page_counter, counter)

    filename = "page_#{String.pad_leading("#{counter}", 4, "0")}.json"
    filepath = Path.join(dir, filename)

    # Write the page data (without crawl_id — it's in the directory name)
    page_data =
      item
      |> Map.drop([:crawl_id])
      |> Jason.encode!(pretty: true)

    File.write!(filepath, page_data)

    Logger.info("Saved page #{counter}: #{item[:url]} → #{filepath}")

    {item, state}
  end
end
