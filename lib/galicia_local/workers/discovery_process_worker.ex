defmodule GaliciaLocal.Workers.DiscoveryProcessWorker do
  @moduledoc """
  Oban worker that processes crawled discovery pages into business listings.

  Automates the pipeline that was previously manual:
    mix discovery.export → ./scripts/process_discovery.sh → mix discovery.import

  Takes a crawl_id, reads crawled pages from disk, sends batches to Claude CLI
  for business extraction, and creates Business records in the database.
  """

  use Oban.Worker,
    queue: :discovery,
    max_attempts: 2,
    unique: [period: 600, fields: [:args, :queue]]

  require Logger

  alias GaliciaLocal.AI.ClaudeCLI
  alias GaliciaLocal.Directory.{Business, DiscoveryCrawl}

  @batch_size 5

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"crawl_id" => crawl_id}}) do
    crawl_dir = Path.join(GaliciaLocal.Scraper.discovery_data_dir(), crawl_id)

    unless File.dir?(crawl_dir) do
      Logger.warning("DiscoveryProcess: crawl directory not found: #{crawl_dir}")
      update_crawl_status(crawl_id, :failed, "crawl directory not found")
      {:error, :crawl_dir_not_found}
    else
      process_crawl(crawl_id, crawl_dir)
    end
  end

  defp process_crawl(crawl_id, crawl_dir) do
    update_crawl_status(crawl_id, :processing)
    metadata = read_metadata(crawl_dir)
    pages = read_pages(crawl_dir)

    if pages == [] do
      Logger.info("DiscoveryProcess [#{crawl_id}]: no pages found, nothing to process")
      update_crawl_status(crawl_id, :completed, {0, 0, 0})
      :ok
    else
      Logger.info("DiscoveryProcess [#{crawl_id}]: processing #{length(pages)} pages")

      context = build_context(metadata)
      batches = Enum.chunk_every(pages, @batch_size)

      {total_created, total_skipped, total_failed} =
        Enum.with_index(batches, 1)
        |> Enum.reduce({0, 0, 0}, fn {batch, batch_num}, {created, skipped, failed} ->
          Logger.info("DiscoveryProcess [#{crawl_id}]: batch #{batch_num}/#{length(batches)}")

          case extract_businesses(batch, context) do
            {:ok, businesses} ->
              {c, s, f} = import_businesses(businesses, context, crawl_id)
              {created + c, skipped + s, failed + f}

            {:error, reason} ->
              Logger.warning("DiscoveryProcess [#{crawl_id}]: batch #{batch_num} failed: #{inspect(reason)}")
              {created, skipped, failed + length(batch)}
          end
        end)

      Logger.info(
        "DiscoveryProcess [#{crawl_id}]: done — #{total_created} created, #{total_skipped} skipped, #{total_failed} failed"
      )

      update_crawl_status(crawl_id, :completed, {total_created, total_skipped, total_failed})
      :ok
    end
  end

  # --- Read crawled data ---

  defp read_metadata(crawl_dir) do
    meta_file = Path.join(crawl_dir, "metadata.json")

    if File.exists?(meta_file) do
      File.read!(meta_file) |> Jason.decode!()
    else
      %{}
    end
  end

  defp read_pages(crawl_dir) do
    crawl_dir
    |> File.ls!()
    |> Enum.filter(&String.starts_with?(&1, "page_"))
    |> Enum.sort()
    |> Enum.map(fn filename ->
      Path.join(crawl_dir, filename)
      |> File.read!()
      |> Jason.decode!()
    end)
  end

  defp build_context(metadata) do
    %{
      region_id: metadata["region_id"],
      city_id: metadata["city_id"],
      category_slugs: get_all_category_slugs(),
      cities: get_all_cities(metadata["region_id"])
    }
  end

  # --- Claude extraction ---

  defp extract_businesses(pages, context) do
    city_list =
      context.cities
      |> Enum.map(fn %{slug: slug, name: name} -> "#{slug} (#{name})" end)
      |> Enum.join(", ")

    category_list = Enum.join(context.category_slugs, ", ")

    pages_json =
      pages
      |> Enum.map(fn page ->
        # Truncate content to keep prompt manageable
        content = String.slice(page["content"] || "", 0, 15_000)

        %{
          url: page["url"],
          title: page["title"],
          headings: Enum.take(page["headings"] || [], 15),
          content: content
        }
      end)
      |> Jason.encode!()

    prompt = """
    You are a data extraction specialist for a business directory helping newcomers.

    Extract ALL individual business listings from these crawled web pages.
    For each business provide:
    - name (required - skip if no name found)
    - address (if available)
    - phone (if available)
    - website (if available)
    - email (if available)
    - city_slug (match to: #{city_list})
    - category_slug (match to: #{category_list})
    - description (brief, from what's on the page)
    - source_url (the page URL where you found this listing)

    Guidelines:
    - Extract EVERY business listing on each page
    - If a page is a listing/search results page, extract all results
    - If a page is a single business detail page, extract that one business
    - If a page has no business listings, return empty array for it
    - Match city_slug by looking at the address or page context
    - Match category_slug by the type of business/service
    - If unsure about city or category, use your best guess or null

    Return ONLY valid JSON (no markdown, no explanation):
    {"businesses": [{"name": "...", "address": "...", "phone": "...", "website": "...", "email": "...", "city_slug": "...", "category_slug": "...", "description": "...", "source_url": "..."}]}

    Pages to process:
    #{pages_json}
    """

    case ClaudeCLI.complete(prompt) do
      {:ok, response} ->
        parse_extraction_response(response)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_extraction_response(response) do
    response
    |> extract_json()
    |> case do
      {:ok, %{"businesses" => businesses}} when is_list(businesses) ->
        valid =
          Enum.filter(businesses, fn b ->
            is_binary(b["name"]) and String.trim(b["name"]) != ""
          end)

        {:ok, valid}

      {:ok, _} ->
        {:error, :unexpected_structure}

      {:error, _} = error ->
        error
    end
  end

  # --- Import businesses ---

  defp import_businesses(businesses, context, crawl_id) do
    cities_map = Map.new(context.cities, fn c -> {c.slug, c} end)
    categories_map = Map.new(context.category_slugs, fn slug -> {slug, slug} end)

    Enum.reduce(businesses, {0, 0, 0}, fn b, {created, skipped, failed} ->
      case create_business(b, cities_map, categories_map, context, crawl_id) do
        :created -> {created + 1, skipped, failed}
        :skipped -> {created, skipped + 1, failed}
        :failed -> {created, skipped, failed + 1}
      end
    end)
  end

  defp create_business(b, cities_map, _categories_map, context, crawl_id) do
    name = String.trim(b["name"] || "")

    if name == "" do
      :failed
    else
      city = cities_map[b["city_slug"]]
      category_id = get_category_id(b["category_slug"])

      attrs = %{
        name: name,
        slug: generate_slug(name),
        address: b["address"],
        phone: b["phone"],
        website: b["website"],
        email: b["email"],
        description: b["description"],
        status: :pending,
        source: :discovery_spider,
        raw_data: %{
          source_url: b["source_url"],
          crawl_id: crawl_id,
          discovered_at: DateTime.utc_now() |> DateTime.to_iso8601()
        },
        city_id: city && city.id,
        category_id: category_id,
        region_id: (city && city.region_id) || context.region_id
      }

      case Business.create(attrs) do
        {:ok, business} ->
          Logger.info("DiscoveryProcess: created #{business.name}")
          :created

        {:error, %Ash.Error.Invalid{}} ->
          :skipped

        {:error, reason} ->
          Logger.warning("DiscoveryProcess: failed to create #{name}: #{inspect(reason)}")
          :failed
      end
    end
  end

  # --- Helpers ---

  defp get_all_category_slugs do
    %{rows: rows} =
      GaliciaLocal.Repo.query!("SELECT slug FROM categories ORDER BY slug")

    Enum.map(rows, fn [slug] -> slug end)
  end

  defp get_all_cities(nil) do
    %{rows: rows} =
      GaliciaLocal.Repo.query!(
        "SELECT slug, name, id::text, region_id::text FROM cities ORDER BY name"
      )

    Enum.map(rows, fn [slug, name, id, region_id] ->
      %{slug: slug, name: name, id: id, region_id: region_id}
    end)
  end

  defp get_all_cities(region_id) do
    %{rows: rows} =
      GaliciaLocal.Repo.query!(
        "SELECT slug, name, id::text, region_id::text FROM cities WHERE region_id = $1 ORDER BY name",
        [Ecto.UUID.dump!(region_id)]
      )

    Enum.map(rows, fn [slug, name, id, rid] ->
      %{slug: slug, name: name, id: id, region_id: rid}
    end)
  end

  defp get_category_id(nil), do: nil

  defp get_category_id(slug) do
    case GaliciaLocal.Repo.query!(
           "SELECT id::text FROM categories WHERE slug = $1 LIMIT 1",
           [slug]
         ) do
      %{rows: [[id]]} -> id
      _ -> nil
    end
  end

  defp generate_slug(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/\s+/, "-")
    |> String.trim("-")
    |> String.slice(0, 100)
  end

  defp extract_json(text) do
    candidates =
      [
        case Regex.run(~r/```(?:json)?\s*\n?([\s\S]*?)\n?```/, text) do
          [_, json] -> String.trim(json)
          _ -> nil
        end,
        String.trim(text),
        slice_outer(text, "{", "}"),
        slice_outer(text, "[", "]")
      ]
      |> Enum.reject(&is_nil/1)

    Enum.find_value(candidates, {:error, {:json_parse_error, String.slice(text, 0, 200)}}, fn
      candidate ->
        case Jason.decode(candidate) do
          {:ok, data} -> {:ok, data}
          {:error, _} -> nil
        end
    end)
  end

  defp slice_outer(text, open, close) do
    with {start, _} <- :binary.match(text, open),
         matches when matches != [] <- :binary.matches(text, close) do
      {last, len} = List.last(matches)
      binary_part(text, start, last - start + len)
    else
      _ -> nil
    end
  end

  # --- DB status tracking ---

  defp update_crawl_status(crawl_id, :processing) do
    case DiscoveryCrawl.get_by_crawl_id(crawl_id) do
      {:ok, crawl} -> DiscoveryCrawl.mark_processing(crawl)
      _ -> :ok
    end
  end

  defp update_crawl_status(crawl_id, :completed, {created, skipped, failed}) do
    case DiscoveryCrawl.get_by_crawl_id(crawl_id) do
      {:ok, crawl} -> DiscoveryCrawl.mark_completed(crawl, created, skipped, failed)
      _ -> :ok
    end
  end

  defp update_crawl_status(crawl_id, :failed, error) do
    case DiscoveryCrawl.get_by_crawl_id(crawl_id) do
      {:ok, crawl} -> DiscoveryCrawl.mark_failed(crawl, error)
      _ -> :ok
    end
  end
end
