defmodule GaliciaLocalWeb.RegionSelectorLive do
  @moduledoc """
  Landing page for selecting a region.
  Users choose their region here before browsing the directory.
  """
  use GaliciaLocalWeb, :live_view

  alias GaliciaLocal.Directory.Region

  @impl true
  def mount(_params, _session, socket) do
    regions = Region.list_active!()

    {:ok,
     socket
     |> assign(:page_title, gettext("Choose Your Region"))
     |> assign(:regions, regions)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-[calc(100vh-3.5rem)] bg-gradient-to-b from-base-200 to-base-100 flex flex-col">
      <div class="flex-1 flex items-center justify-center px-4 py-12">
        <div class="max-w-4xl w-full">
          <div class="text-center mb-16">
            <p class="text-primary font-medium mb-3 tracking-wide uppercase text-sm">
              {gettext("Welcome to StartLocal")}
            </p>
            <h1 class="text-4xl md:text-5xl lg:text-6xl font-bold text-base-content mb-6 leading-tight">
              {gettext("Where are you")} <br class="hidden sm:block" />
              <span class="text-primary">{gettext("settling in?")}</span>
            </h1>
            <p class="text-lg md:text-xl text-base-content/60 max-w-xl mx-auto">
              {gettext("Discover local businesses, services, and insider tips from the community.")}
            </p>
          </div>

          <div class="grid grid-cols-1 sm:grid-cols-2 gap-6 max-w-2xl mx-auto">
            <%= for region <- @regions do %>
              <.link
                navigate={~p"/#{region.slug}"}
                class="group relative overflow-hidden rounded-2xl bg-base-100 shadow-lg hover:shadow-xl transition-all duration-300 hover:-translate-y-1 border border-base-300 hover:border-primary/50"
              >
                <div class="absolute inset-0 bg-gradient-to-br from-primary/5 to-transparent opacity-0 group-hover:opacity-100 transition-opacity duration-300"></div>
                <div class="relative p-8 text-center">
                  <div class="text-7xl mb-5 transform group-hover:scale-110 transition-transform duration-300">
                    {region_flag(region.country_code)}
                  </div>
                  <h2 class="text-2xl font-bold text-base-content mb-2 group-hover:text-primary transition-colors">
                    {Gettext.gettext(GaliciaLocalWeb.Gettext, region.name)}
                  </h2>
                  <p class="text-base-content/50 text-sm mb-6 leading-relaxed">
                    {region_tagline(region.slug)}
                  </p>
                  <span class="inline-flex items-center gap-2 text-primary font-medium">
                    {gettext("Explore")}
                    <span class="hero-arrow-right w-4 h-4 group-hover:translate-x-1 transition-transform"></span>
                  </span>
                </div>
              </.link>
            <% end %>
          </div>
        </div>
      </div>

      <footer class="text-center py-6 text-base-content/40 text-sm">
        <p>{gettext("Helping newcomers feel at home since 2026")}</p>
      </footer>
    </div>
    """
  end

  defp region_flag("ES"), do: "🇪🇸"
  defp region_flag("NL"), do: "🇳🇱"
  defp region_flag(_), do: "🌍"

  defp region_tagline("galicia"), do: gettext("Celtic heritage, incredible seafood, warm communities")
  defp region_tagline("netherlands"), do: gettext("Cycling culture, canals, welcoming expat scene")
  defp region_tagline(_), do: ""
end
