defmodule GaliciaLocal.Directory.Types.Language do
  @moduledoc """
  Languages that a business may speak/support.
  """
  use Ash.Type.Enum,
    values: [
      es: [description: "Spanish (Español)", label: "Spanish"],
      en: [description: "English", label: "English"],
      gl: [description: "Galician (Galego)", label: "Galician"],
      pt: [description: "Portuguese (Português)", label: "Portuguese"],
      de: [description: "German (Deutsch)", label: "German"],
      fr: [description: "French (Français)", label: "French"],
      nl: [description: "Dutch (Nederlands)", label: "Dutch"],
      it: [description: "Italian (Italiano)", label: "Italian"],
      he: [description: "Hebrew (עברית)", label: "Hebrew"]
    ]
end
