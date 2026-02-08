defmodule GaliciaLocalWeb.CitiesLive do
  @moduledoc """
  Cities index page showing all cities.
  """
  use GaliciaLocalWeb, :live_view

  alias GaliciaLocal.Directory.City

  @impl true
  def mount(_params, _session, socket) do
    region = socket.assigns[:current_region]
    tenant_opts = if region, do: [tenant: region.id], else: []
    region_name = if region, do: Gettext.gettext(GaliciaLocalWeb.Gettext, region.name), else: gettext("Galicia")
    region_slug = if region, do: region.slug, else: "galicia"

    is_admin = is_map(socket.assigns[:current_user]) and socket.assigns.current_user.is_admin == true

    cities =
      City.list!(tenant_opts)
      |> Ash.load!([:business_count, :public_business_count, :translations], tenant_opts)
      |> Enum.sort_by(& &1.population, :desc)

    cities =
      if is_admin do
        cities
      else
        Enum.filter(cities, fn city -> (city.public_business_count || 0) > 0 end)
      end

    {:ok,
     socket
     |> assign(:page_title, gettext("Cities in %{region}", region: region_name))
     |> assign(:meta_description, gettext("Explore all cities in %{region}. Find local businesses and integrate into %{region} life.", region: region_name))
     |> assign(:cities, cities)
     |> assign(:region_name, region_name)
     |> assign(:region_slug, region_slug)
     |> assign(:is_admin, is_admin)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-100">
      <div class="container mx-auto max-w-6xl px-4 py-8">
        <!-- Header -->
        <div class="text-center mb-12">
          <h1 class="text-4xl font-bold text-base-content mb-4">{gettext("Explore %{region}", region: @region_name)}</h1>
          <p class="text-base-content/70 max-w-2xl mx-auto">
            {gettext("Discover the beautiful cities and towns of %{region}. Each place has its own charm and character.", region: @region_name)}
          </p>
        </div>

        <!-- Map -->
        <div
          id="cities-map"
          class="h-96 bg-base-200 rounded-xl mb-10 shadow-lg"
          phx-hook="CitiesMap"
          data-region={@region_slug}
          data-cities={Jason.encode!(Enum.map(@cities, fn city ->
            %{
              name: city.name,
              slug: city.slug,
              province: city.province,
              lat: city.latitude && Decimal.to_float(city.latitude),
              lng: city.longitude && Decimal.to_float(city.longitude),
              business_count: (if @is_admin, do: city.business_count, else: city.public_business_count) || 0
            }
          end))}
        >
          <div class="flex items-center justify-center h-full text-base-content/50">
            <span class="hero-map w-12 h-12 mr-3"></span>
            <p>{gettext("Loading map...")}</p>
          </div>
        </div>

        <!-- Cities Grid -->
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          <%= for city <- @cities do %>
            <.link navigate={~p"/#{@region_slug}/cities/#{city.slug}"} class="group">
              <div class="card bg-base-100 shadow-xl overflow-hidden transition-all group-hover:scale-105 group-hover:shadow-2xl">
                <figure class="relative h-48">
                  <img
                    src={city.image_url || "https://images.unsplash.com/photo-1558618666-fcd25c85cd64?w=600"}
                    alt={city.name}
                    class="w-full h-full object-cover"
                  />
                  <div class="absolute inset-0 bg-gradient-to-t from-black/70 via-black/20 to-transparent"></div>
                  <%= if city.featured do %>
                    <span class="absolute top-4 right-4 badge badge-primary">{gettext("Featured")}</span>
                  <% end %>
                  <%= if @is_admin and (city.business_count || 0) == 0 do %>
                    <span class="absolute top-4 left-4 badge badge-warning badge-sm">{gettext("Admin only")}</span>
                  <% end %>
                  <div class="absolute bottom-4 left-4 right-4">
                    <h2 class="text-2xl font-bold text-white">{city.name}</h2>
                    <p class="text-white/80">{city.province}</p>
                  </div>
                </figure>
                <div class="card-body">
                  <p class="text-base-content/70 line-clamp-3">
                    {localized(city, :description, @locale)}
                  </p>
                  <div class="flex justify-between items-center mt-4">
                    <div class="flex gap-2">
                      <span class="badge badge-outline">{ngettext("1 listing", "%{count} listings", if(@is_admin, do: city.business_count, else: city.public_business_count) || 0)}</span>
                      <%= if city.population do %>
                        <span class="badge badge-ghost">{gettext("%{population} pop.", population: format_population(city.population))}</span>
                      <% end %>
                    </div>
                    <span class="text-primary group-hover:translate-x-1 transition-transform">
                      {gettext("Explore →")}
                    </span>
                  </div>
                </div>
              </div>
            </.link>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp format_population(pop) when pop >= 1_000_000, do: "#{div(pop, 1_000_000)}M+"
  defp format_population(pop) when pop >= 1_000, do: "#{div(pop, 1_000)}K+"
  defp format_population(pop), do: "#{pop}"
end
