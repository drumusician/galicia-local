defmodule GaliciaLocal.Directory.Types.BusinessStatus do
  @moduledoc """
  Status of a business listing in the directory.

  Flow: :pending → :researching → :researched → :enriched → :verified
  """
  use Ash.Type.Enum,
    values: [
      pending: [description: "Awaiting website/search research", label: "Pending"],
      researching: [description: "Website crawling and web search in progress", label: "Researching"],
      researched: [description: "Research complete, awaiting LLM enrichment", label: "Researched"],
      enriched: [description: "LLM enrichment completed", label: "Enriched"],
      verified: [description: "Manually verified by admin", label: "Verified"],
      rejected: [description: "Rejected/spam/closed", label: "Rejected"]
    ]
end
