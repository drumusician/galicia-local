defmodule GaliciaLocalWeb.PageController do
  use GaliciaLocalWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end

  def about(conn, _params) do
    render(conn, :about, page_title: "About")
  end

  def contact(conn, _params) do
    render(conn, :contact, page_title: "Contact")
  end

  def privacy(conn, _params) do
    render(conn, :privacy, page_title: "Privacy Policy")
  end

  def set_locale(conn, %{"locale" => locale}) when locale in ~w(en es nl) do
    conn
    |> put_session("locale", locale)
    |> redirect(to: get_referrer(conn))
  end

  def set_locale(conn, _params) do
    redirect(conn, to: "/")
  end

  def set_region(conn, %{"region" => region_slug}) do
    alias GaliciaLocal.Directory.Region

    case Region.get_by_slug(region_slug) do
      {:ok, _region} ->
        redirect_path = conn.params["redirect_to"] || get_referrer(conn)

        conn
        |> put_session("region", region_slug)
        |> put_flash(:info, "Switched to #{region_slug}")
        |> redirect(to: redirect_path)

      {:error, _} ->
        conn
        |> put_flash(:error, "Region not found")
        |> redirect(to: get_referrer(conn))
    end
  end

  defp get_referrer(conn) do
    case get_req_header(conn, "referer") do
      [referer | _] ->
        uri = URI.parse(referer)
        path = uri.path || "/"
        if uri.query, do: "#{path}?#{uri.query}", else: path

      _ ->
        "/"
    end
  end
end
