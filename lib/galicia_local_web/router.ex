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
    plug GaliciaLocalWeb.Plugs.SetLocale
  end

  pipeline :with_region do
    plug GaliciaLocalWeb.Plugs.SetRegion
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :load_from_bearer
    plug :set_actor, :user
  end

  pipeline :require_admin do
    plug :require_admin_user
  end

  # Root routes (no region required)
  scope "/", GaliciaLocalWeb do
    pipe_through :browser

    # Region selector landing page
    ash_authentication_live_session :landing_routes,
      on_mount: [{GaliciaLocalWeb.LiveUserAuth, :live_user_optional}] do
      live "/", RegionSelectorLive, :index
    end

    # Locale switching
    post "/locale", PageController, :set_locale

    # Static pages (global)
    get "/about", PageController, :about
    get "/contact", PageController, :contact
    get "/privacy", PageController, :privacy

    # Auth routes (global)
    auth_routes AuthController, GaliciaLocal.Accounts.User, path: "/auth"
    sign_out_route AuthController

    sign_in_route register_path: "/register",
                  reset_path: "/reset",
                  auth_routes_prefix: "/auth",
                  on_mount: [{GaliciaLocalWeb.LiveUserAuth, :live_no_user}],
                  overrides: [
                    GaliciaLocalWeb.AuthOverrides,
                    Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI
                  ]

    reset_route auth_routes_prefix: "/auth",
                overrides: [
                  GaliciaLocalWeb.AuthOverrides,
                  Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI
                ]

    confirm_route GaliciaLocal.Accounts.User, :confirm_new_user,
      auth_routes_prefix: "/auth",
      overrides: [
        GaliciaLocalWeb.AuthOverrides,
        Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI
      ]

    magic_sign_in_route(GaliciaLocal.Accounts.User, :magic_link,
      auth_routes_prefix: "/auth",
      overrides: [
        GaliciaLocalWeb.AuthOverrides,
        Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI
      ]
    )
  end

  # Admin routes (global, with region switcher)
  scope "/", GaliciaLocalWeb do
    pipe_through [:browser, :with_region]

    ash_authentication_live_session :admin_routes,
      on_mount: [{GaliciaLocalWeb.LiveUserAuth, :live_admin_required}] do
      live "/admin", Admin.DashboardLive, :index
      live "/admin/scraper", Admin.ScraperLive, :index
      live "/admin/businesses", Admin.BusinessesLive, :index
      live "/admin/businesses/:id/edit", Admin.EditBusinessLive
      live "/admin/cities", Admin.CitiesLive, :index
      live "/admin/categories", Admin.CategoriesLive, :index
      live "/admin/analytics", Admin.AnalyticsLive, :index
      live "/admin/claims", Admin.ClaimsLive, :index
      live "/admin/users", Admin.UsersLive, :index
    end

    # Region switching (for admin)
    post "/region", PageController, :set_region
    get "/region", PageController, :set_region
  end

  # Region-specific home pages
  scope "/galicia", GaliciaLocalWeb do
    pipe_through [:browser, :with_region]

    ash_authentication_live_session :galicia_home,
      on_mount: [{GaliciaLocalWeb.LiveUserAuth, :live_user_optional}] do
      live "/", GaliciaHomeLive, :index
    end
  end

  scope "/netherlands", GaliciaLocalWeb do
    pipe_through [:browser, :with_region]

    ash_authentication_live_session :netherlands_home,
      on_mount: [{GaliciaLocalWeb.LiveUserAuth, :live_user_optional}] do
      live "/", NetherlandsHomeLive, :index
    end
  end

  # Region-scoped public routes (shared across all regions)
  scope "/:region", GaliciaLocalWeb do
    pipe_through [:browser, :with_region]

    ash_authentication_live_session :region_public_routes,
      on_mount: [{GaliciaLocalWeb.LiveUserAuth, :live_user_optional}] do
      live "/search", SearchLive, :index
      live "/cities", CitiesLive, :index
      live "/cities/:slug", CityLive, :show
      live "/categories", CategoriesLive, :index
      live "/categories/:slug", CategoryLive, :show
      live "/businesses/:id", BusinessLive, :show
      live "/members/:id", MemberLive, :show
    end

    ash_authentication_live_session :region_member_routes,
      on_mount: [{GaliciaLocalWeb.LiveUserAuth, :live_user_required}] do
      live "/profile", ProfileLive, :edit
      live "/favorites", FavoritesLive, :index
      live "/businesses/:id/claim", ClaimBusinessLive, :new
      live "/my-businesses", MyBusinessesLive, :index
      live "/my-businesses/:id/edit", EditBusinessLive, :edit
      live "/recommend", RecommendBusinessLive, :new
    end
  end

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
