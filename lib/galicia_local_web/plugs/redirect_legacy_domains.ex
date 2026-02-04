defmodule GaliciaLocalWeb.Plugs.RedirectLegacyDomains do
  @moduledoc """
  Redirects legacy domains and handles region subdomain routing.

  - galicialocal.com, www.galicialocal.com → galicia.startlocal.app
  - galicialocal.es, www.galicialocal.es → galicia.startlocal.app
  - galicia.startlocal.app/ → galicia.startlocal.app/galicia (root path only)
  - netherlands.startlocal.app/ → netherlands.startlocal.app/netherlands (root path only)
  """
  import Plug.Conn

  @legacy_domains [
    "galicialocal.com",
    "www.galicialocal.com",
    "galicialocal.es",
    "www.galicialocal.es"
  ]

  @target_host "galicia.startlocal.app"

  @base_domains ["startlocal.app", "localhost"]
  @known_regions ["galicia", "netherlands"]

  def init(opts), do: opts

  def call(conn, _opts) do
    cond do
      conn.host in @legacy_domains ->
        redirect_to_new_domain(conn)

      region = region_from_subdomain(conn) ->
        maybe_redirect_to_region_path(conn, region)

      true ->
        conn
    end
  end

  defp redirect_to_new_domain(conn) do
    path = conn.request_path
    query = if conn.query_string != "", do: "?#{conn.query_string}", else: ""

    new_url = "https://#{@target_host}#{path}#{query}"

    conn
    |> put_resp_header("location", new_url)
    |> send_resp(301, "")
    |> halt()
  end

  defp region_from_subdomain(conn) do
    host = conn.host || ""

    Enum.find_value(@base_domains, fn base_domain ->
      case String.split(host, ".#{base_domain}") do
        [subdomain, ""] when subdomain in @known_regions ->
          subdomain

        _ ->
          nil
      end
    end)
  end

  defp maybe_redirect_to_region_path(conn, region) do
    if conn.request_path == "/" do
      query = if conn.query_string != "", do: "?#{conn.query_string}", else: ""
      new_url = "/#{region}#{query}"

      conn
      |> put_resp_header("location", new_url)
      |> send_resp(302, "")
      |> halt()
    else
      conn
    end
  end
end
