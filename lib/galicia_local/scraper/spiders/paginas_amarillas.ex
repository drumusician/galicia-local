defmodule GaliciaLocal.Scraper.Spiders.PaginasAmarillas do
  @moduledoc """
  Crawly spider for scraping business listings from Páginas Amarillas (Spanish Yellow Pages).

  ## Usage

      # Start the spider with options
      Crawly.Engine.start_spider(__MODULE__, city: "ourense", category: "abogados")

      # Or from IEx
      GaliciaLocal.Scraper.scrape(:paginas_amarillas, city: "ourense", category: "abogados")
  """

  use Crawly.Spider

  require Logger

  @base "https://www.paginasamarillas.es"

  @impl Crawly.Spider
  def base_url, do: @base

  @impl Crawly.Spider
  def init(opts) do
    city = Keyword.get(opts, :city, "ourense")
    category = Keyword.get(opts, :category, "abogados")
    city_id = Keyword.get(opts, :city_id)
    category_id = Keyword.get(opts, :category_id)

    # Store context for later use in parse_item
    :persistent_term.put({__MODULE__, :context}, %{
      city: city,
      city_id: city_id,
      category: category,
      category_id: category_id
    })

    # Build search URL
    # Format: /search/abogados/all-ma/ourense/all-is/ourense/all-ba/all-pu/all-nc/
    search_url = "#{@base}/search/#{category}/all-ma/#{city}/all-is/#{city}/all-ba/all-pu/all-nc/"

    Logger.info("Starting Páginas Amarillas spider: #{search_url}")

    [start_urls: [search_url]]
  end

  @impl Crawly.Spider
  def parse_item(response) do
    {:ok, document} = Floki.parse_document(response.body)
    context = :persistent_term.get({__MODULE__, :context}, %{})

    # Extract business listings from search results
    listings =
      document
      |> Floki.find(".listado-item, .resultado")
      |> Enum.map(fn listing ->
        parse_listing(listing, context)
      end)
      |> Enum.reject(&is_nil/1)

    # Find pagination links
    next_pages =
      document
      |> Floki.find(".pagination a, .paginacion a")
      |> Enum.map(fn link ->
        href = Floki.attribute(link, "href") |> List.first()
        if href && String.starts_with?(href, "/"), do: @base <> href, else: href
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.map(&Crawly.Utils.request_from_url/1)

    Logger.info("Found #{length(listings)} listings on page, #{length(next_pages)} pagination links")

    %Crawly.ParsedItem{
      items: listings,
      requests: next_pages
    }
  end

  defp parse_listing(listing, context) do
    name =
      listing
      |> Floki.find("h2 a, .nombre-comercio, .business-name")
      |> Floki.text()
      |> String.trim()

    if name == "" do
      nil
    else
      address =
        listing
        |> Floki.find(".direccion, .address, [itemprop='streetAddress']")
        |> Floki.text()
        |> String.trim()

      phone =
        listing
        |> Floki.find(".telefono a, .phone, [itemprop='telephone']")
        |> Floki.text()
        |> String.trim()
        |> clean_phone()

      website =
        listing
        |> Floki.find("a.web, a[rel='nofollow']")
        |> Floki.attribute("href")
        |> List.first()

      # Extract detail page URL for more info
      detail_url =
        listing
        |> Floki.find("h2 a, .nombre-comercio a")
        |> Floki.attribute("href")
        |> List.first()

      # Generate a unique place_id from the detail URL or name+address
      place_id =
        if detail_url do
          detail_url |> String.split("/") |> List.last() |> String.replace(".html", "")
        else
          :crypto.hash(:md5, "#{name}#{address}") |> Base.encode16(case: :lower)
        end

      %{
        place_id: "pa_#{place_id}",
        name: name,
        address: address,
        phone: phone,
        website: clean_url(website),
        source: :paginas_amarillas,
        spider: "PaginasAmarillas",
        city_id: context[:city_id],
        category_id: context[:category_id],
        scraped_from: context[:city]
      }
    end
  end

  defp clean_phone(nil), do: nil
  defp clean_phone(""), do: nil

  defp clean_phone(phone) do
    phone
    |> String.replace(~r/[^\d+]/, "")
    |> case do
      "" -> nil
      cleaned -> cleaned
    end
  end

  defp clean_url(nil), do: nil
  defp clean_url(""), do: nil

  defp clean_url(url) do
    cond do
      String.starts_with?(url, "http") -> url
      String.starts_with?(url, "//") -> "https:" <> url
      String.starts_with?(url, "/") -> @base <> url
      true -> nil
    end
  end

  @impl Crawly.Spider
  def override_settings do
    [
      closespider_itemcount: 100,
      concurrent_requests_per_domain: 1,
      follow_redirects: true
    ]
  end
end
