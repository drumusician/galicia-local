defmodule GaliciaLocalWeb.ErrorJSONTest do
  use GaliciaLocalWeb.ConnCase, async: true

  test "renders 404" do
    assert GaliciaLocalWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert GaliciaLocalWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
