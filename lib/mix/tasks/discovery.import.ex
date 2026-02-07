defmodule Mix.Tasks.Discovery.Import do
  @shortdoc "Import discovered businesses from Claude Code extraction results"
  @moduledoc """
  Reads JSON result files produced by Claude Code (via process_discovery.sh)
  and creates businesses in the database.

  ## Usage

      mix discovery.import --dir tmp/discovery_batches/abc123
      mix discovery.import --file tmp/discovery_batches/abc123/batch_001_result.json
      mix discovery.import --dir tmp/discovery_batches/abc123 --dry-run

  ## Expected JSON format

  ```json
  {
    "businesses": [
      {
        "name": "Business Name",
        "address": "123 Main St, Amsterdam",
        "phone": "+31 20 123 4567",
        "website": "https://example.nl",
        "email": "info@example.nl",
        "city_slug": "amsterdam",
        "category_slug": "restaurants",
        "description": "A nice restaurant...",
        "source_url": "https://directory.nl/listing/123"
      }
    ],
    "pages_processed": 5,
    "businesses_found": 12
  }
  ```

  ## Options

      --dir DIR       Process all *_result.json files in directory
      --file FILE     Process a single result file
      --dry-run       Show what would be imported without writing to DB
  """

  use Mix.Task

  require Logger

  alias GaliciaLocal.Directory.Business

  @impl Mix.Task
  def run(argv) do
    {:ok, _} = Application.ensure_all_started(:postgrex)
    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    {:ok, _} = Application.ensure_all_started(:ash)
    {:ok, _} = GaliciaLocal.Repo.start_link()

    {opts, _, _} =
      OptionParser.parse(argv, switches: [dir: :string, file: :string, dry_run: :boolean])

    dry_run? = opts[:dry_run] || false
    files = resolve_result_files(opts)

    # Pre-load city and category lookup maps
    cities = load_cities()
    categories = load_categories()

    Mix.shell().info("Processing #{length(files)} discovery result file(s)")
    Mix.shell().info("Known cities: #{map_size(cities)}, categories: #{map_size(categories)}")

    if dry_run?, do: Mix.shell().info("[DRY RUN MODE]")

    {total_created, total_skipped, total_failed} =
      Enum.reduce(files, {0, 0, 0}, fn file, {created, skipped, failed} ->
        Mix.shell().info("")
        Mix.shell().info("Reading #{file}...")

        data = file |> File.read!() |> Jason.decode!()
        businesses = data["businesses"] || []

        # Infer crawl_id from directory name
        crawl_id = file |> Path.dirname() |> Path.basename()

        Mix.shell().info("  #{length(businesses)} businesses (crawl: #{crawl_id})")

        if dry_run? do
          Enum.each(Enum.take(businesses, 5), fn b ->
            city = b["city_slug"] || "?"
            cat = b["category_slug"] || "?"
            Mix.shell().info("    [#{city}/#{cat}] #{b["name"]}")
          end)

          if length(businesses) > 5 do
            Mix.shell().info("    ... and #{length(businesses) - 5} more")
          end

          {created + length(businesses), skipped, failed}
        else
          {batch_created, batch_skipped, batch_failed} =
            Enum.reduce(businesses, {0, 0, 0}, fn b, {c, s, f} ->
              case create_business(b, cities, categories, crawl_id) do
                :created -> {c + 1, s, f}
                :skipped -> {c, s + 1, f}
                :failed -> {c, s, f + 1}
              end
            end)

          Mix.shell().info(
            "  Done: #{batch_created} created, #{batch_skipped} skipped, #{batch_failed} failed"
          )

          {created + batch_created, skipped + batch_skipped, failed + batch_failed}
        end
      end)

    Mix.shell().info("")
    prefix = if dry_run?, do: "[DRY RUN] Would create", else: "Created"

    Mix.shell().info(
      "#{prefix} #{total_created} businesses (#{total_skipped} skipped, #{total_failed} failed)"
    )
  end

  defp create_business(b, cities, categories, crawl_id) do
    name = (b["name"] || "") |> String.trim()

    if name == "" do
      Logger.warning("Skipping business with no name")
      :failed
    else
      slug = generate_slug(name)
      city = cities[b["city_slug"]]
      category = categories[b["category_slug"]]

      attrs = %{
        name: name,
        slug: slug,
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
        category_id: category && category.id,
        region_id: city && city.region_id
      }

      case Business.create(attrs) do
        {:ok, business} ->
          Logger.info("Created: #{business.name} (#{b["city_slug"]}/#{b["category_slug"]})")
          :created

        {:error, %Ash.Error.Invalid{}} ->
          Logger.debug("Duplicate, skipping: #{name}")
          :skipped

        {:error, reason} ->
          Logger.warning("Failed to create #{name}: #{inspect(reason)}")
          :failed
      end
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

  defp load_cities do
    %{rows: rows} =
      GaliciaLocal.Repo.query!(
        "SELECT slug, id, region_id FROM cities ORDER BY slug"
      )

    Map.new(rows, fn [slug, id, region_id] ->
      {slug,
       %{
         id: Ecto.UUID.cast!(id),
         region_id: if(region_id, do: Ecto.UUID.cast!(region_id))
       }}
    end)
  end

  defp load_categories do
    %{rows: rows} =
      GaliciaLocal.Repo.query!(
        "SELECT slug, id FROM categories ORDER BY slug"
      )

    Map.new(rows, fn [slug, id] ->
      {slug, %{id: Ecto.UUID.cast!(id)}}
    end)
  end

  defp resolve_result_files(opts) do
    cond do
      opts[:file] ->
        file = opts[:file]
        unless File.exists?(file), do: Mix.raise("File not found: #{file}")
        [file]

      opts[:dir] ->
        dir = opts[:dir]
        unless File.dir?(dir), do: Mix.raise("Directory not found: #{dir}")

        dir
        |> File.ls!()
        |> Enum.filter(&String.ends_with?(&1, "_result.json"))
        |> Enum.sort()
        |> Enum.map(&Path.join(dir, &1))
        |> case do
          [] -> Mix.raise("No *_result.json files found in #{dir}")
          files -> files
        end

      true ->
        Mix.raise("Provide --dir or --file")
    end
  end
end
