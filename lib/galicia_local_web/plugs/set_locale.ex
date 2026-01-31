defmodule GaliciaLocalWeb.Plugs.SetLocale do
  @moduledoc """
  Reads locale from session and sets it for Gettext.
  Falls back to Accept-Language header, then default "en".
  """
  import Plug.Conn

  @supported_locales ~w(en es)

  def init(opts), do: opts

  def call(conn, _opts) do
    locale =
      get_session(conn, "locale") ||
        parse_accept_language(conn) ||
        "en"

    locale = if locale in @supported_locales, do: locale, else: "en"

    Gettext.put_locale(GaliciaLocalWeb.Gettext, locale)
    assign(conn, :locale, locale)
  end

  defp parse_accept_language(conn) do
    case get_req_header(conn, "accept-language") do
      [header | _] ->
        header
        |> String.split(",")
        |> Enum.map(fn part ->
          part |> String.trim() |> String.split(";") |> List.first() |> String.split("-") |> List.first()
        end)
        |> Enum.find(&(&1 in @supported_locales))

      _ ->
        nil
    end
  end
end
