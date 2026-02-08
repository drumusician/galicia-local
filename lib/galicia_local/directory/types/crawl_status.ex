defmodule GaliciaLocal.Directory.Types.CrawlStatus do
  use Ash.Type.Enum,
    values: [
      crawling: "Spider is actively crawling pages",
      crawled: "Spider finished, pages saved to disk",
      processing: "DiscoveryProcessWorker is extracting businesses",
      completed: "Processing finished successfully",
      failed: "Crawl or processing failed"
    ]
end
