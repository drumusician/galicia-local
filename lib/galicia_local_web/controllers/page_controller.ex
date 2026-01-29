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
end
