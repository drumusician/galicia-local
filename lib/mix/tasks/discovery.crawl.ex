defmodule Mix.Tasks.Discovery.Crawl do
  @shortdoc "Start a discovery crawl on one or more URLs"
  @moduledoc """
  Crawls a website and saves raw page content for later extraction by Claude Code.

  ## Usage

      mix discovery.crawl https://example.nl/bedrijven/amsterdam
      mix discovery.crawl https://site1.nl https://site2.nl --max-pages 50
      mix discovery.crawl --seed-file seeds/nl_lawyers.txt --city amsterdam --category lawyers

  ## Options

      --city SLUG         Target city slug (for context in extraction)
      --category SLUG     Target category slug (for context in extraction)
      --region SLUG       Target region slug (default: inferred from city)
      --max-pages N       Maximum pages to crawl (default: 200)
      --crawl-id ID       Custom crawl ID (default: auto-generated)
      --seed-file FILE    Read seed URLs from file (one per line)

  ## Output

  Pages are saved to `tmp/discovery_crawls/<crawl_id>/`.
  Next step: `mix discovery.export --crawl-id <id>`
  """

  use Mix.Task

  require Logger

  @impl Mix.Task
  def run(argv) do
    {:ok, _} = Application.ensure_all_started(:postgrex)
    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    {:ok, _} = Application.ensure_all_started(:ash)
    {:ok, _} = GaliciaLocal.Repo.start_link()

    {opts, urls, _} =
      OptionParser.parse(argv,
        switches: [
          city: :string,
          category: :string,
          region: :string,
          max_pages: :integer,
          crawl_id: :string,
          seed_file: :string
        ]
      )

    # Collect URLs from args and seed file
    file_urls =
      case opts[:seed_file] do
        nil ->
          []

        file ->
          unless File.exists?(file), do: Mix.raise("Seed file not found: #{file}")

          file
          |> File.read!()
          |> String.split("\n")
          |> Enum.map(&String.trim/1)
          |> Enum.reject(fn line -> line == "" || String.starts_with?(line, "#") end)
      end

    seed_urls = urls ++ file_urls

    if seed_urls == [] do
      Mix.raise("Provide at least one URL or --seed-file")
    end

    # Resolve city/category IDs
    city_id = resolve_city_id(opts[:city])
    category_id = resolve_category_id(opts[:category])

    region_id =
      cond do
        opts[:region] -> resolve_region_id(opts[:region])
        city_id -> get_city_region_id(city_id)
        true -> nil
      end

    # Disable Crawly's HTTP API to avoid port conflict with running Phoenix app
    Application.put_env(:crawly, :start_http_api?, false)
    {:ok, _} = Application.ensure_all_started(:crawly)

    crawl_opts = [
      max_pages: opts[:max_pages] || 200,
      city_id: city_id,
      category_id: category_id,
      region_id: region_id
    ]

    crawl_opts =
      if opts[:crawl_id],
        do: Keyword.put(crawl_opts, :crawl_id, opts[:crawl_id]),
        else: crawl_opts

    Mix.shell().info("Starting discovery crawl...")
    Mix.shell().info("  Seed URLs: #{length(seed_urls)}")
    Mix.shell().info("  Max pages: #{crawl_opts[:max_pages]}")

    case GaliciaLocal.Scraper.crawl_directory(seed_urls, crawl_opts) do
      {:ok, crawl_id} ->
        Mix.shell().info("  Crawl ID: #{crawl_id}")
        Mix.shell().info("")
        Mix.shell().info("Spider started. Monitoring progress...")
        monitor_crawl(crawl_id)

      {:error, reason} ->
        Mix.raise("Failed to start crawl: #{inspect(reason)}")
    end
  end

  defp monitor_crawl(crawl_id) do
    dir = Path.join("tmp/discovery_crawls", crawl_id)

    # Poll for completion
    Stream.interval(2_000)
    |> Enum.reduce_while(0, fn _, prev_count ->
      page_count =
        case File.ls(dir) do
          {:ok, files} -> Enum.count(files, &String.starts_with?(&1, "page_"))
          _ -> 0
        end

      if page_count > prev_count do
        Mix.shell().info("  #{page_count} pages crawled...")
      end

      # Check if spider is still running
      spiders = Crawly.Engine.running_spiders()

      if map_size(spiders) == 0 and page_count > 0 do
        Mix.shell().info("")
        Mix.shell().info("Crawl complete: #{page_count} pages saved to #{dir}/")
        Mix.shell().info("")
        Mix.shell().info("Next steps:")
        Mix.shell().info("  mix discovery.export --crawl-id #{crawl_id}")
        Mix.shell().info("  ./scripts/process_discovery.sh #{crawl_id} 1 N")
        Mix.shell().info("  mix discovery.import --dir tmp/discovery_batches/#{crawl_id}")
        {:halt, page_count}
      else
        {:cont, page_count}
      end
    end)
  end

  defp resolve_city_id(nil), do: nil

  defp resolve_city_id(slug) do
    import Ecto.Query

    case GaliciaLocal.Repo.one(from(c in "cities", where: c.slug == ^slug, select: c.id)) do
      nil -> Mix.raise("City not found: #{slug}")
      id -> Ecto.UUID.cast!(id)
    end
  end

  defp resolve_category_id(nil), do: nil

  defp resolve_category_id(slug) do
    import Ecto.Query

    case GaliciaLocal.Repo.one(from(c in "categories", where: c.slug == ^slug, select: c.id)) do
      nil -> Mix.raise("Category not found: #{slug}")
      id -> Ecto.UUID.cast!(id)
    end
  end

  defp resolve_region_id(slug) do
    import Ecto.Query

    case GaliciaLocal.Repo.one(from(r in "regions", where: r.slug == ^slug, select: r.id)) do
      nil -> Mix.raise("Region not found: #{slug}")
      id -> Ecto.UUID.cast!(id)
    end
  end

  defp get_city_region_id(city_id) do
    import Ecto.Query

    GaliciaLocal.Repo.one(
      from(c in "cities", where: c.id == type(^city_id, Ecto.UUID), select: c.region_id)
    )
    |> case do
      nil -> nil
      id -> Ecto.UUID.cast!(id)
    end
  end
end
