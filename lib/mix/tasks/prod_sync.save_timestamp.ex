defmodule Mix.Tasks.ProdSync.SaveTimestamp do
  @shortdoc "Save current UTC timestamp for prod sync tracking"
  @moduledoc """
  Saves the current UTC timestamp to `tmp/prod_sync/last_sync.txt`.

  Run this after a successful push to mark the sync point.

      mix prod_sync.save_timestamp
  """

  use Mix.Task

  @timestamp_file "tmp/prod_sync/last_sync.txt"

  @impl Mix.Task
  def run(_argv) do
    File.mkdir_p!(Path.dirname(@timestamp_file))
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    File.write!(@timestamp_file, timestamp)
    Mix.shell().info("Saved sync timestamp: #{timestamp}")
  end
end
