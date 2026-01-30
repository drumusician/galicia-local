defmodule GaliciaLocalWeb.Router do
  use GaliciaLocalWeb, :router

  import Oban.Web.Router
  use AshAuthentication.Phoenix.Router

  import AshAuthentication.Plug.Helpers

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {GaliciaLocalWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :load_from_session
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :load_from_bearer
    plug :set_actor, :user
  end

  pipeline :require_admin do
    plug :require_admin_user
  end

  scope "/", GaliciaLocalWeb do
    pipe_through :browser

    ash_authentication_live_session :authenticated_routes,
      on_mount: [{GaliciaLocalWeb.LiveUserAuth, :live_user_optional}] do
      # Public routes that may have a logged in user
      live "/", HomeLive, :index
      live "/search", SearchLive, :index
      live "/cities", CitiesLive, :index
      live "/cities/:slug", CityLive, :show
      live "/categories", CategoriesLive, :index
      live "/categories/:slug", CategoryLive, :show
      live "/businesses/:id", BusinessLive, :show
      live "/members/:id", MemberLive, :show
    end

    ash_authentication_live_session :member_routes,
      on_mount: [{GaliciaLocalWeb.LiveUserAuth, :live_user_required}] do
      live "/profile", ProfileLive, :edit
    end

    ash_authentication_live_session :admin_routes,
      on_mount: [{GaliciaLocalWeb.LiveUserAuth, :live_admin_required}] do
      # Admin routes (protected by on_mount)
      live "/admin", Admin.DashboardLive, :index
      live "/admin/scraper", Admin.ScraperLive, :index
      live "/admin/businesses", Admin.BusinessesLive, :index
      live "/admin/cities", Admin.CitiesLive, :index
      live "/admin/categories", Admin.CategoriesLive, :index
    end

    # Static pages
    get "/about", PageController, :about
    get "/contact", PageController, :contact
    get "/privacy", PageController, :privacy

    # Auth routes
    auth_routes AuthController, GaliciaLocal.Accounts.User, path: "/auth"
    sign_out_route AuthController

    # Remove these if you'd like to use your own authentication views
    sign_in_route register_path: "/register",
                  reset_path: "/reset",
                  auth_routes_prefix: "/auth",
                  on_mount: [{GaliciaLocalWeb.LiveUserAuth, :live_no_user}],
                  overrides: [
                    GaliciaLocalWeb.AuthOverrides,
                    Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI
                  ]

    # Remove this if you do not want to use the reset password feature
    reset_route auth_routes_prefix: "/auth",
                overrides: [
                  GaliciaLocalWeb.AuthOverrides,
                  Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI
                ]

    # Remove this if you do not use the confirmation strategy
    confirm_route GaliciaLocal.Accounts.User, :confirm_new_user,
      auth_routes_prefix: "/auth",
      overrides: [
        GaliciaLocalWeb.AuthOverrides,
        Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI
      ]

    # Remove this if you do not use the magic link strategy.
    magic_sign_in_route(GaliciaLocal.Accounts.User, :magic_link,
      auth_routes_prefix: "/auth",
      overrides: [
        GaliciaLocalWeb.AuthOverrides,
        Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI
      ]
    )
  end

  # Other scopes may use custom stacks.
  # scope "/api", GaliciaLocalWeb do
  #   pipe_through :api
  # end

  import Phoenix.LiveDashboard.Router

  scope "/admin" do
    pipe_through [:browser, :require_admin]

    live_dashboard "/dashboard", metrics: GaliciaLocalWeb.Telemetry
  end

  # Swoosh mailbox preview in development
  if Application.compile_env(:galicia_local, :dev_routes) do
    scope "/dev" do
      pipe_through :browser

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  scope "/" do
    pipe_through :browser

    oban_dashboard("/admin/oban", resolver: GaliciaLocalWeb.ObanResolver)
  end

  defp require_admin_user(conn, _opts) do
    user = conn.assigns[:current_user]

    if user && user.is_admin do
      conn
    else
      conn
      |> Phoenix.Controller.redirect(to: "/")
      |> Plug.Conn.halt()
    end
  end
end
