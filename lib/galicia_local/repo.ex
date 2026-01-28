defmodule GaliciaLocal.Repo do
  use Ecto.Repo,
    otp_app: :galicia_local,
    adapter: Ecto.Adapters.Postgres
end
