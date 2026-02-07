defmodule GaliciaLocal.AI.ClaudeCLI do
  @moduledoc """
  Client for calling Claude via the CLI (`claude --print`) using a Max plan subscription.

  This avoids API costs by using the authenticated CLI tool instead of the API.
  The `ANTHROPIC_API_KEY` env var is explicitly cleared to force Max plan usage.
  """
  require Logger

  @timeout 300_000

  @doc """
  Send a prompt to Claude via the CLI and return the response.
  Returns `{:ok, response_text}` or `{:error, reason}`.
  """
  def complete(prompt, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @timeout)

    unless cli_available?() do
      Logger.warning("claude CLI not found in PATH, returning error")
      {:error, :cli_not_available}
    else
      do_request(prompt, timeout)
    end
  end

  defp do_request(prompt, timeout) do
    args = ["--print", prompt]

    Logger.info("ClaudeCLI: starting request (timeout: #{timeout}ms)")
    start_time = System.monotonic_time(:millisecond)

    try do
      case System.cmd("claude", args,
             stderr_to_stdout: true,
             env: [{"ANTHROPIC_API_KEY", ""}],
             timeout: timeout
           ) do
        {output, 0} ->
          duration = System.monotonic_time(:millisecond) - start_time
          trimmed = String.trim(output)
          Logger.info("ClaudeCLI: completed in #{duration}ms (#{byte_size(trimmed)} bytes)")
          {:ok, trimmed}

        {output, exit_code} ->
          duration = System.monotonic_time(:millisecond) - start_time

          Logger.error(
            "ClaudeCLI: failed with exit code #{exit_code} after #{duration}ms: #{String.slice(output, 0, 500)}"
          )

          {:error, {:exit_code, exit_code, output}}
      end
    rescue
      e ->
        Logger.error("ClaudeCLI: exception: #{inspect(e)}")
        {:error, {:exception, e}}
    end
  end

  @doc """
  Check if the `claude` CLI is available in PATH.
  """
  def cli_available? do
    case System.find_executable("claude") do
      nil -> false
      _path -> true
    end
  end
end
