defmodule GaliciaLocalWeb.Plugs.SetLocale do
  @moduledoc """
  Reads locale from session and sets it for Gettext.
  Uses the current region's supported locales and default locale.
  Falls back to Accept-Language header, then region default, then "en".
  """
  import Plug.Conn

  @fallback_locales ~w(en es nl)
  @default_locale "en"

  def init(opts), do: opts

  def call(conn, _opts) do
    region = conn.assigns[:current_region]
    supported_locales = get_supported_locales(region)
    default_locale = get_default_locale(region)

    locale =
      get_session(conn, "locale") ||
        parse_accept_language(conn, supported_locales) ||
        default_locale

    locale = if locale in supported_locales, do: locale, else: default_locale

    Gettext.put_locale(GaliciaLocalWeb.Gettext, locale)
    assign(conn, :locale, locale)
  end

  defp get_supported_locales(nil), do: @fallback_locales
  defp get_supported_locales(region), do: region.supported_locales || @fallback_locales

  defp get_default_locale(nil), do: @default_locale
  defp get_default_locale(region), do: region.default_locale || @default_locale

  defp parse_accept_language(conn, supported_locales) do
    case get_req_header(conn, "accept-language") do
      [header | _] ->
        header
        |> String.split(",")
        |> Enum.map(fn part ->
          part |> String.trim() |> String.split(";") |> List.first() |> String.split("-") |> List.first()
        end)
        |> Enum.find(&(&1 in supported_locales))

      _ ->
        nil
    end
  end
end
