defmodule GaliciaLocalWeb.Plugs.SetRegion do
  @moduledoc """
  Sets the current region from path params or session.
  For path-based routing: /:region/cities, /:region/businesses, etc.
  Stores the region in session and makes it available in conn.assigns as :current_region.
  """
  import Plug.Conn

  alias GaliciaLocal.Directory.Region

  @default_region "galicia"

  def init(opts), do: opts

  def call(conn, _opts) do
    region_slug = get_region_slug(conn)

    case Region.get_by_slug(region_slug) do
      {:ok, region} ->
        conn
        |> assign(:current_region, region)
        |> put_session("region", region.slug)

      {:error, _} ->
        # Region not found in path, try session or default
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
    # Priority: path params > first path segment > session > default
    # For routes like /:region/cities, the region comes from path_params
    # For routes like /galicia or /netherlands, extract from first path segment
    conn.path_params["region"] ||
      extract_region_from_path(conn.request_path) ||
      get_session(conn, "region") ||
      @default_region
  end

  defp extract_region_from_path(path) do
    case String.split(path, "/", trim: true) do
      [first | _] when first in ["galicia", "netherlands"] -> first
      _ -> nil
    end
  end
end
