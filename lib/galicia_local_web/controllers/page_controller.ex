defmodule GaliciaLocalWeb.PageController do
  use GaliciaLocalWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
