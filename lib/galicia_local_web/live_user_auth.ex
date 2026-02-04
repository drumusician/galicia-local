defmodule GaliciaLocalWeb.LiveUserAuth do
  @moduledoc """
  Helpers for authenticating users in LiveViews.
  Also handles region context for multi-tenancy.
  """

  import Phoenix.Component
  use GaliciaLocalWeb, :verified_routes

  alias GaliciaLocal.Directory.Region

  @default_region "galicia"

  # This is used for nested liveviews to fetch the current user.
  # To use, place the following at the top of that liveview:
  # on_mount {GaliciaLocalWeb.LiveUserAuth, :current_user}
  def on_mount(:current_user, _params, session, socket) do
    {:cont, AshAuthentication.Phoenix.LiveSession.assign_new_resources(socket, session)}
  end

  def on_mount(:live_user_optional, params, session, socket) do
    set_locale(session)
    socket = set_region(socket, params, session)

    if socket.assigns[:current_user] do
      {:cont, assign(socket, :locale, Gettext.get_locale(GaliciaLocalWeb.Gettext))}
    else
      {:cont, socket |> assign(:current_user, nil) |> assign(:locale, Gettext.get_locale(GaliciaLocalWeb.Gettext))}
    end
  end

  def on_mount(:live_user_required, params, session, socket) do
    set_locale(session)
    socket = set_region(socket, params, session)

    if socket.assigns[:current_user] do
      {:cont, assign(socket, :locale, Gettext.get_locale(GaliciaLocalWeb.Gettext))}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/sign-in")}
    end
  end

  def on_mount(:live_no_user, params, session, socket) do
    set_locale(session)
    socket = set_region(socket, params, session)

    if socket.assigns[:current_user] do
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/")}
    else
      {:cont, socket |> assign(:current_user, nil) |> assign(:locale, Gettext.get_locale(GaliciaLocalWeb.Gettext))}
    end
  end

  def on_mount(:live_admin_required, params, session, socket) do
    set_locale(session)
    socket = set_region(socket, params, session)
    user = socket.assigns[:current_user]

    cond do
      is_nil(user) ->
        {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/sign-in")}

      user.is_admin != true ->
        {:halt,
         socket
         |> Phoenix.LiveView.put_flash(:error, "You don't have permission to access this page.")
         |> Phoenix.LiveView.redirect(to: ~p"/")}

      true ->
        {:cont, assign(socket, :locale, Gettext.get_locale(GaliciaLocalWeb.Gettext))}
    end
  end

  defp set_locale(session) do
    locale = session["locale"] || "en"
    Gettext.put_locale(GaliciaLocalWeb.Gettext, locale)
  end

  defp set_region(socket, params, session) do
    # Priority: path params > session > default
    region_slug = params["region"] || session["region"] || @default_region

    case Region.get_by_slug(region_slug) do
      {:ok, region} ->
        assign(socket, :current_region, region)

      {:error, _} ->
        # Fallback to default region
        case Region.get_by_slug(@default_region) do
          {:ok, region} -> assign(socket, :current_region, region)
          {:error, _} -> assign(socket, :current_region, nil)
        end
    end
  end
end
