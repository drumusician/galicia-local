defmodule GaliciaLocalWeb.Plugs.SetRegion do
  @moduledoc """
  Sets the current region from subdomain, path params, or session.

  Priority order:
  1. Subdomain (galicia.startlocal.app, netherlands.startlocal.app)
  2. Path params (/:region/cities)
  3. First path segment (/galicia, /netherlands)
  4. Session
  5. Default (galicia)

  Stores the region in session and makes it available in conn.assigns as :current_region.
  """
  import Plug.Conn

  alias GaliciaLocal.Directory.Region

  @default_region "galicia"
  @known_regions ["galicia", "netherlands"]
  # Base domains where we look for region subdomains
  @base_domains ["startlocal.app", "localhost"]

  def init(opts), do: opts

  def call(conn, _opts) do
    region_slug = get_region_slug(conn)

    case Region.get_by_slug(region_slug) do
      {:ok, region} ->
        conn
        |> assign(:current_region, region)
        |> put_session("region", region.slug)

      {:error, _} ->
        # Region not found, try session or default
        fallback_slug = get_session(conn, "region") || @default_region

        case Region.get_by_slug(fallback_slug) do
          {:ok, region} ->
            conn
            |> assign(:current_region, region)
            |> put_session("region", region.slug)

          {:error, _} ->
            # No regions exist at all, continue without region context
            assign(conn, :current_region, nil)
        end
    end
  end

  defp get_region_slug(conn) do
    # Priority: subdomain > path params > first path segment > session > default
    extract_region_from_subdomain(conn) ||
      conn.path_params["region"] ||
      extract_region_from_path(conn.request_path) ||
      get_session(conn, "region") ||
      @default_region
  end

  defp extract_region_from_subdomain(conn) do
    host = conn.host || ""

    # Check if host matches pattern: region.base_domain
    Enum.find_value(@base_domains, fn base_domain ->
      case String.split(host, ".#{base_domain}") do
        [subdomain, ""] when subdomain in @known_regions ->
          subdomain

        _ ->
          nil
      end
    end)
  end

  defp extract_region_from_path(path) do
    case String.split(path, "/", trim: true) do
      [first | _] when first in @known_regions -> first
      _ -> nil
    end
  end
end
