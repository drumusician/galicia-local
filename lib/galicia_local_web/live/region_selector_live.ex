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
    <div class="min-h-screen bg-gradient-to-br from-primary/5 via-base-100 to-secondary/5 flex items-center justify-center p-4">
      <div class="max-w-4xl w-full">
        <div class="text-center mb-12">
          <h1 class="text-4xl md:text-5xl font-bold text-base-content mb-4">
            {gettext("Welcome")}
          </h1>
          <p class="text-xl text-base-content/70 max-w-2xl mx-auto">
            {gettext("Your local guide to settling in. Find businesses, services, and tips from people who've been there.")}
          </p>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-6 max-w-2xl mx-auto">
          <%= for region <- @regions do %>
            <.link
              navigate={~p"/#{region.slug}"}
              class="card bg-base-100 shadow-xl hover:shadow-2xl transition-all duration-300 hover:-translate-y-1 border-2 border-transparent hover:border-primary"
            >
              <div class="card-body items-center text-center py-10">
                <div class="text-6xl mb-4">
                  {region_flag(region.country_code)}
                </div>
                <h2 class="card-title text-2xl">{region.name}</h2>
                <p class="text-base-content/60">
                  {region_description(region.slug)}
                </p>
                <div class="mt-4">
                  <span class="btn btn-primary btn-sm">
                    {gettext("Explore")} →
                  </span>
                </div>
              </div>
            </.link>
          <% end %>
        </div>

        <div class="text-center mt-12 text-base-content/50 text-sm">
          <p>{gettext("More regions coming soon...")}</p>
        </div>
      </div>
    </div>
    """
  end

  defp region_flag("ES"), do: "🇪🇸"
  defp region_flag("NL"), do: "🇳🇱"
  defp region_flag(_), do: "🌍"

  defp region_description("galicia"), do: gettext("Northwest Spain - Celtic heritage, incredible seafood, and warm communities")
  defp region_description("netherlands"), do: gettext("The Netherlands - Cycling culture, canals, and a welcoming international scene")
  defp region_description(_), do: ""
end
