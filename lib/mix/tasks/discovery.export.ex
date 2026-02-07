defmodule Mix.Tasks.Discovery.Export do
  @shortdoc "Export crawled pages as JSON batches for Claude Code extraction"
  @moduledoc """
  Reads raw page files from a discovery crawl and batches them for
  processing by Claude Code.

  ## Usage

      mix discovery.export --crawl-id abc123
      mix discovery.export --crawl-id abc123 --batch-size 5

  ## Options

      --crawl-id ID       The crawl ID to export (required)
      --batch-size N      Pages per batch (default: 5)

  ## Output

  Batches are written to `tmp/discovery_batches/<crawl_id>/`.
  Next step: `./scripts/process_discovery.sh <crawl_id> 1 N`
  """

  use Mix.Task

  @impl Mix.Task
  def run(argv) do
    {:ok, _} = Application.ensure_all_started(:postgrex)
    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    {:ok, _} = GaliciaLocal.Repo.start_link()

    {opts, _, _} =
      OptionParser.parse(argv, switches: [crawl_id: :string, batch_size: :integer])

    crawl_id = opts[:crawl_id] || Mix.raise("--crawl-id is required")
    batch_size = opts[:batch_size] || 5

    crawl_dir = Path.join("tmp/discovery_crawls", crawl_id)
    unless File.dir?(crawl_dir), do: Mix.raise("Crawl directory not found: #{crawl_dir}")

    # Read metadata
    metadata = read_metadata(crawl_dir)

    # Read all page files
    pages =
      crawl_dir
      |> File.ls!()
      |> Enum.filter(&String.starts_with?(&1, "page_"))
      |> Enum.sort()
      |> Enum.map(fn filename ->
        Path.join(crawl_dir, filename)
        |> File.read!()
        |> Jason.decode!()
      end)

    total = length(pages)
    Mix.shell().info("Found #{total} crawled pages for crawl #{crawl_id}")

    if total == 0 do
      Mix.shell().info("Nothing to export!")
    else
      # Get context data for Claude
      all_category_slugs = get_all_category_slugs()
      all_cities = get_all_cities(metadata["region_id"])

      batches = Enum.chunk_every(pages, batch_size)
      batch_dir = Path.join("tmp/discovery_batches", crawl_id)
      File.mkdir_p!(batch_dir)

      # Clear old batches
      batch_dir |> File.ls!() |> Enum.each(&File.rm!(Path.join(batch_dir, &1)))

      Enum.each(Enum.with_index(batches, 1), fn {batch_pages, batch_num} ->
        data = %{
          type: "discovery_extraction",
          crawl_id: crawl_id,
          batch: batch_num,
          total_batches: length(batches),
          count: length(batch_pages),
          context: %{
            region_id: metadata["region_id"],
            target_city_id: metadata["city_id"],
            target_category_id: metadata["category_id"],
            all_category_slugs: all_category_slugs,
            all_cities: all_cities
          },
          pages: batch_pages
        }

        file = Path.join(batch_dir, "batch_#{String.pad_leading("#{batch_num}", 3, "0")}.json")
        File.write!(file, Jason.encode!(data, pretty: true))
        Mix.shell().info("  Wrote #{file} (#{length(batch_pages)} pages)")
      end)

      Mix.shell().info("")
      Mix.shell().info("Exported #{total} pages in #{length(batches)} batches to #{batch_dir}/")
      Mix.shell().info("")
      Mix.shell().info("Next: ./scripts/process_discovery.sh #{crawl_id} 1 #{length(batches)}")
    end
  end

  defp read_metadata(crawl_dir) do
    meta_file = Path.join(crawl_dir, "metadata.json")

    if File.exists?(meta_file) do
      File.read!(meta_file) |> Jason.decode!()
    else
      %{}
    end
  end

  defp get_all_category_slugs do
    %{rows: rows} =
      GaliciaLocal.Repo.query!("SELECT slug FROM categories ORDER BY slug")

    Enum.map(rows, fn [slug] -> slug end)
  end

  defp get_all_cities(nil) do
    %{rows: rows} =
      GaliciaLocal.Repo.query!("SELECT slug, name FROM cities ORDER BY name")

    Enum.map(rows, fn [slug, name] -> %{slug: slug, name: name} end)
  end

  defp get_all_cities(region_id) do
    %{rows: rows} =
      GaliciaLocal.Repo.query!(
        "SELECT slug, name FROM cities WHERE region_id = $1::uuid ORDER BY name",
        [Ecto.UUID.dump!(region_id)]
      )

    Enum.map(rows, fn [slug, name] -> %{slug: slug, name: name} end)
  end
end
