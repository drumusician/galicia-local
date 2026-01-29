defmodule GaliciaLocal.Directory.Types.ScrapeSource do
  @moduledoc """
  Source from which business data was scraped.
  """
  use Ash.Type.Enum,
    values: [
      google_maps: [description: "Google Maps / Places API", label: "Google Maps"],
      paginas_amarillas: [description: "Páginas Amarillas (Spanish Yellow Pages)", label: "Páginas Amarillas"],
      tripadvisor: [description: "TripAdvisor reviews and listings", label: "TripAdvisor"],
      manual: [description: "Manually entered data", label: "Manual Entry"],
      web_scrape: [description: "General web scraping", label: "Web Scrape"]
    ]
end
