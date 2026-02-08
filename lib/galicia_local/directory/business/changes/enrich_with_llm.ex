defmodule GaliciaLocal.Directory.Business.Changes.EnrichWithLLM do
  @moduledoc """
  Ash change that enriches business data using Claude.

  Uses the CLI (`claude --print` via Max plan) when available, falling back
  to the API. Both paths share the `Enrichment` module for prompt building
  and response parsing.
  """
  use Ash.Resource.Change

  require Logger

  alias GaliciaLocal.Directory.Business.Enrichment

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      business = changeset.data

      business = Enrichment.load_relationships(business)
      research_data = Enrichment.load_research_data(business.id)

      case enrich_business(business, research_data) do
        {:ok, enriched_data} ->
          changeset
          |> Ash.Changeset.force_change_attributes(enriched_data)
          |> Ash.Changeset.force_change_attribute(:status, :enriched)
          |> Ash.Changeset.force_change_attribute(:last_enriched_at, DateTime.utc_now())

        {:error, reason} ->
          Logger.error("Failed to enrich business #{business.id}: #{inspect(reason)}")
          changeset
      end
    end)
  end

  defp enrich_business(business, research_data) do
    prompt = Enrichment.build_prompt(business, research_data)
    max_tokens = if Enrichment.has_research_data?(research_data), do: 3000, else: 2048

    if cli_enrichment_enabled?() do
      case GaliciaLocal.AI.ClaudeCLI.complete(prompt) do
        {:ok, response} ->
          Enrichment.parse_response(response)

        {:error, :cli_not_available} ->
          Logger.info("CLI not available, falling back to API")
          api_enrich(prompt, max_tokens)

        {:error, _} = error ->
          error
      end
    else
      api_enrich(prompt, max_tokens)
    end
  end

  defp api_enrich(prompt, max_tokens) do
    case GaliciaLocal.AI.Claude.complete(prompt, max_tokens: max_tokens) do
      {:ok, response} -> Enrichment.parse_response(response)
      {:error, _} = error -> error
    end
  end

  defp cli_enrichment_enabled? do
    System.get_env("ENABLE_CLI_ENRICHMENT") in ["true", "1"]
  end
end
