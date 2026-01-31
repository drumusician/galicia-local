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

  def set_locale(conn, %{"locale" => locale}) when locale in ~w(en es) do
    conn
    |> put_session("locale", locale)
    |> redirect(to: get_referrer(conn))
  end

  def set_locale(conn, _params) do
    redirect(conn, to: "/")
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
