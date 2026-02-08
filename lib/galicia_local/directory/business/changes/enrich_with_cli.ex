defmodule GaliciaLocal.Directory.Business.Changes.EnrichWithCLI do
  @moduledoc """
  Ash change that enriches business data using the Claude CLI (Max plan).

  Identical enrichment quality to `EnrichWithLLM` but uses `claude --print`
  instead of the API, avoiding per-request costs.

  Set `ENABLE_CLI_ENRICHMENT=true` to activate. When not set, the change
  is a no-op (the cron still fires but does nothing).
  """
  use Ash.Resource.Change

  require Logger

  alias GaliciaLocal.Directory.Business.Enrichment

  @impl true
  def change(changeset, _opts, _context) do
    if cli_enrichment_enabled?() do
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
            Logger.error("CLI enrichment failed for business #{business.id}: #{inspect(reason)}")
            changeset
        end
      end)
    else
      changeset
    end
  end

  defp enrich_business(business, research_data) do
    prompt = Enrichment.build_prompt(business, research_data)

    case GaliciaLocal.AI.ClaudeCLI.complete(prompt) do
      {:ok, response} -> Enrichment.parse_response(response)
      {:error, _} = error -> error
    end
  end

  defp cli_enrichment_enabled? do
    System.get_env("ENABLE_CLI_ENRICHMENT") in ["true", "1"]
  end
end
