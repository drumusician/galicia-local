defmodule GaliciaLocalWeb.Plugs.RedirectLegacyDomains do
  @moduledoc """
  Redirects legacy domains to their new subdomain equivalents.

  - galicialocal.com, www.galicialocal.com → galicia.startlocal.app
  - galicialocal.es, www.galicialocal.es → galicia.startlocal.app
  """
  import Plug.Conn

  @legacy_domains [
    "galicialocal.com",
    "www.galicialocal.com",
    "galicialocal.es",
    "www.galicialocal.es"
  ]

  @target_host "galicia.startlocal.app"

  def init(opts), do: opts

  def call(conn, _opts) do
    if conn.host in @legacy_domains do
      redirect_to_new_domain(conn)
    else
      conn
    end
  end

  defp redirect_to_new_domain(conn) do
    # Preserve the path and query string
    path = conn.request_path
    query = if conn.query_string != "", do: "?#{conn.query_string}", else: ""

    new_url = "https://#{@target_host}#{path}#{query}"

    conn
    |> put_resp_header("location", new_url)
    |> send_resp(301, "")
    |> halt()
  end
end
