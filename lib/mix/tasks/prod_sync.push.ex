defmodule Mix.Tasks.ProdSync.Push do
  @shortdoc "Push exported SQL changes to production via psql"
  @moduledoc """
  Reads a SQL file and executes it on the production database using `psql`.

  Requires `PROD_DATABASE_URL` environment variable to be set with the
  Supabase connection string, e.g.:

      export PROD_DATABASE_URL="postgresql://postgres.xxhnzolttaxyrkitwdcg:[PASSWORD]@aws-0-eu-central-1.pooler.supabase.com:6543/postgres"

  Usage:

      mix prod_sync.push tmp/prod_sync/changes.sql
      mix prod_sync.push tmp/prod_sync/changes.sql --dry-run

  Options:

      --dry-run   Print statement count without executing
  """

  use Mix.Task

  @impl Mix.Task
  def run(argv) do
    {opts, args, _} =
      OptionParser.parse(argv, switches: [dry_run: :boolean])

    sql_file =
      case args do
        [file] -> file
        _ -> Mix.raise("Usage: mix prod_sync.push <sql_file> [--dry-run]")
      end

    unless File.exists?(sql_file) do
      Mix.raise("SQL file not found: #{sql_file}")
    end

    dry_run? = opts[:dry_run] || false
    sql = File.read!(sql_file)
    statements = parse_statements(sql)
    file_size = File.stat!(sql_file).size |> format_bytes()

    Mix.shell().info("Found #{length(statements)} statements in #{sql_file} (#{file_size})")

    if dry_run? do
      Mix.shell().info("[DRY RUN] Would execute #{length(statements)} statements")

      statements
      |> Enum.take(10)
      |> Enum.each(fn stmt ->
        preview = stmt |> String.slice(0, 120) |> String.replace("\n", " ")
        Mix.shell().info("  #{preview}...")
      end)

      if length(statements) > 10 do
        Mix.shell().info("  ... and #{length(statements) - 10} more")
      end
    else
      db_url = System.get_env("PROD_DATABASE_URL") ||
        Mix.raise("""
        PROD_DATABASE_URL not set. Export it first:

          export PROD_DATABASE_URL="postgresql://postgres.xxhnzolttaxyrkitwdcg:[PASSWORD]@aws-0-eu-central-1.pooler.supabase.com:6543/postgres"

        You can find the connection string in your Supabase dashboard under Settings > Database.
        """)

      Mix.shell().info("Executing against production database...")

      {output, exit_code} =
        System.cmd("psql", [db_url, "-f", sql_file, "--set", "ON_ERROR_STOP=on"],
          stderr_to_stdout: true
        )

      if exit_code != 0 do
        Mix.shell().error("psql failed:")
        Mix.shell().error(output)
        Mix.raise("Push failed with exit code #{exit_code}")
      end

      update_count =
        output
        |> String.split("\n")
        |> Enum.count(&String.starts_with?(&1, "UPDATE"))

      insert_count =
        output
        |> String.split("\n")
        |> Enum.count(&String.starts_with?(&1, "INSERT"))

      Mix.shell().info("Done! #{update_count} updates, #{insert_count} inserts executed.")
      Mix.shell().info("Run `mix prod_sync.save_timestamp` to mark this sync point.")
    end
  end

  defp parse_statements(sql) do
    sql
    |> String.split("\n")
    |> Enum.reject(fn line ->
      trimmed = String.trim(line)
      trimmed == "" or String.starts_with?(trimmed, "--")
    end)
    |> Enum.join("\n")
    |> String.split(";")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&(&1 <> ";"))
  end

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"
end
