defmodule GaliciaLocal.Secrets do
  use AshAuthentication.Secret

  def secret_for(
        [:authentication, :tokens, :signing_secret],
        GaliciaLocal.Accounts.User,
        _opts,
        _context
      ) do
    Application.fetch_env(:galicia_local, :token_signing_secret)
  end
end
