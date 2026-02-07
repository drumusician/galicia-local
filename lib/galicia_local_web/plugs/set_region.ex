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
  Region slugs are cached in :persistent_term with a 5-minute TTL to avoid DB queries on every request.
  """
  import Plug.Conn

  alias GaliciaLocal.Directory.Region

  @default_region "galicia"
  @base_domains ["startlocal.app", "localhost"]
  @cache_key :known_region_slugs
  @cache_ttl_ms :timer.minutes(5)

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
    extract_region_from_subdomain(conn) ||
      conn.path_params["region"] ||
      extract_region_from_path(conn.request_path) ||
      get_session(conn, "region") ||
      @default_region
  end

  defp extract_region_from_subdomain(conn) do
    host = conn.host || ""
    known = known_region_slugs()

    Enum.find_value(@base_domains, fn base_domain ->
      case String.split(host, ".#{base_domain}") do
        [subdomain, ""] when is_binary(subdomain) ->
          if subdomain in known, do: subdomain, else: nil

        _ ->
          nil
      end
    end)
  end

  defp extract_region_from_path(path) do
    known = known_region_slugs()

    case String.split(path, "/", trim: true) do
      [first | _] when is_binary(first) ->
        if first in known, do: first, else: nil

      _ ->
        nil
    end
  end

  @doc """
  Returns cached list of known region slugs. Refreshes from DB every 5 minutes.
  """
  def known_region_slugs do
    case :persistent_term.get(@cache_key, nil) do
      {slugs, expires_at} when is_list(slugs) ->
        if System.monotonic_time(:millisecond) < expires_at do
          slugs
        else
          refresh_cache()
        end

      _ ->
        refresh_cache()
    end
  end

  defp refresh_cache do
    slugs =
      try do
        Region.list_active!()
        |> Enum.map(& &1.slug)
      rescue
        _ -> ["galicia", "netherlands"]
      end

    expires_at = System.monotonic_time(:millisecond) + @cache_ttl_ms
    :persistent_term.put(@cache_key, {slugs, expires_at})
    slugs
  end
end
