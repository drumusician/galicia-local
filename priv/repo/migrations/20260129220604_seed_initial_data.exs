defmodule GaliciaLocal.Repo.Migrations.SeedInitialData do
  use Ecto.Migration

  def up do
    sql_file = Path.join(:code.priv_dir(:galicia_local), "repo/seed_data_inserts.sql")

    statements =
      sql_file
      |> File.read!()
      |> String.split("\n")
      |> Enum.filter(fn line ->
        trimmed = String.trim(line)
        String.starts_with?(trimmed, "INSERT INTO")
      end)
      |> Enum.map(fn line ->
        String.replace(line, ");", ") ON CONFLICT DO NOTHING;")
      end)

    for statement <- statements do
      repo().query!(statement)
    end
  end

  def down do
    execute("DELETE FROM scrape_jobs")
    execute("DELETE FROM businesses")
    execute("DELETE FROM cities")
    execute("DELETE FROM categories")
  end
end
