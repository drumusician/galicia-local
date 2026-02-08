defmodule GaliciaLocalWeb.RegionHomeLive do
  @moduledoc """
  Unified home page LiveView for any region.
  Loads phrases, cultural tips, hero image, etc. from region.settings.
  Replaces the region-specific GaliciaHomeLive and NetherlandsHomeLive.
  """
  use GaliciaLocalWeb, :live_view

  require Ash.Query

  alias GaliciaLocal.Directory.{City, Category, Business}

  @impl true
  def mount(_params, _session, socket) do
    region = socket.assigns[:current_region]
    tenant_opts = if region, do: [tenant: region.id], else: []
    is_admin = is_map(socket.assigns[:current_user]) and socket.assigns.current_user.is_admin == true

    featured_cities =
      City.featured!(tenant_opts)
      |> Ash.load!([:business_count, :translations], tenant_opts)
      |> then(fn cities ->
        if is_admin, do: cities, else: Enum.filter(cities, fn c -> (c.business_count || 0) > 0 end)
      end)

    categories_by_priority =
      Category.list!()
      |> Ash.load!(:translations)
      |> Enum.group_by(& &1.priority)
      |> Enum.sort_by(fn {priority, _} -> priority end)

    recent_businesses =
      Business.recent!(tenant_opts)
      |> Ash.load!([:city, :category], tenant_opts)

    total_businesses =
      Business
      |> Ash.Query.filter(status in [:enriched, :verified] and not is_nil(description) and not is_nil(summary))
      |> Ash.count!(tenant_opts)

    local_gems_count =
      Business
      |> Ash.Query.filter(local_gem_score > 0.7 and status in [:enriched, :verified])
      |> then(fn query ->
        if region, do: Ash.Query.set_tenant(query, region.id), else: query
      end)
      |> Ash.count!()

    cities_count =
      if is_admin do
        Ash.count!(City, tenant_opts)
      else
        City.list!(tenant_opts)
        |> Ash.load!(:business_count, tenant_opts)
        |> Enum.count(fn c -> (c.business_count || 0) > 0 end)
      end

    settings = (region && region.settings) || %{}
    phrases = settings["phrases"] || []
    tips = settings["cultural_tips"] || []

    random_phrase = if phrases != [], do: Enum.random(phrases), else: nil
    random_tips = if tips != [], do: Enum.take_random(tips, 3), else: []

    region_name = if region, do: Gettext.gettext(GaliciaLocalWeb.Gettext, region.name), else: "Region"
    region_slug = if region, do: region.slug, else: "galicia"
    hero_image_url = (region && region.hero_image_url) || "https://images.unsplash.com/photo-1558618666-fcd25c85cd64?w=1920&q=80"

    # Determine the secondary locale for categories (first non-en locale)
    secondary_locale =
      if region do
        region.supported_locales
        |> Enum.reject(&(&1 == "en"))
        |> List.first()
      end

    {:ok,
     socket
     |> assign(:page_title, gettext("Integrate into %{region} Life", region: region_name))
     |> assign(:meta_description, gettext("Discover %{count}+ local businesses across %{cities} cities. Find restaurants, legal help, services and learn local customs to truly integrate into %{region} life.", count: total_businesses, cities: cities_count, region: region_name))
     |> assign(:featured_cities, featured_cities)
     |> assign(:categories_by_priority, categories_by_priority)
     |> assign(:recent_businesses, recent_businesses)
     |> assign(:total_businesses, total_businesses)
     |> assign(:local_gems_count, local_gems_count)
     |> assign(:cities_count, cities_count)
     |> assign(:phrase, random_phrase)
     |> assign(:all_phrases, phrases)
     |> assign(:cultural_tips, random_tips)
     |> assign(:search_query, "")
     |> assign(:region_name, region_name)
     |> assign(:region_slug, region_slug)
     |> assign(:hero_image_url, hero_image_url)
     |> assign(:secondary_locale, secondary_locale)}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    region_slug = socket.assigns.region_slug

    if String.trim(query) != "" do
      {:noreply, push_navigate(socket, to: ~p"/#{region_slug}/search?q=#{query}")}
    else
      {:noreply, socket}
    end
  end

  def handle_event("new_phrase", _, socket) do
    phrases = socket.assigns.all_phrases

    if phrases != [] do
      {:noreply, assign(socket, :phrase, Enum.random(phrases))}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen">
      <%!-- Hero Section --%>
      <section class="hero min-h-[80vh] relative">
        <div
          class="absolute inset-0 bg-cover bg-center"
          style={"background-image: url('#{@hero_image_url}');"}
        >
        </div>
        <div class="absolute inset-0 bg-black/50"></div>
        <div class="hero-content text-center text-neutral-content py-20">
          <div class="max-w-3xl">
            <p class="mb-4 text-lg opacity-90 tracking-wide uppercase">{gettext("Welcome to %{region}", region: @region_name)}</p>
            <h1 class="mb-6 text-5xl md:text-6xl lg:text-7xl font-bold leading-tight">
              {gettext("Make %{region} Your Home", region: @region_name)}
            </h1>
            <p class="mb-10 text-lg md:text-xl opacity-90 max-w-2xl mx-auto leading-relaxed">
              {gettext("Discover local businesses, learn local customs, and truly integrate into your new community.")}
            </p>

            <form phx-submit="search" class="form-control w-full max-w-xl mx-auto mb-8">
              <div class="join w-full shadow-xl">
                <input
                  type="text"
                  name="query"
                  value={@search_query}
                  placeholder={gettext("Search for lawyers, restaurants, services...")}
                  class="input input-lg join-item flex-1 bg-base-100 text-base-content focus:outline-none"
                />
                <button type="submit" class="btn btn-primary btn-lg join-item px-8">
                  <span class="hero-magnifying-glass w-5 h-5"></span>
                  <span class="hidden sm:inline">{gettext("Search")}</span>
                </button>
              </div>
            </form>

            <div class="flex flex-wrap justify-center gap-3">
              <.link navigate={~p"/#{@region_slug}/search?filter=local-gems"} class="btn btn-outline btn-sm text-white border-white/50 hover:bg-white hover:text-neutral hover:border-white">
                <span class="hero-star w-4 h-4"></span>
                {gettext("Local Gems")}
              </.link>
              <.link navigate={~p"/#{@region_slug}/categories/restaurants"} class="btn btn-outline btn-sm text-white border-white/50 hover:bg-white hover:text-neutral hover:border-white">
                {gettext("Restaurants")}
              </.link>
              <.link navigate={~p"/#{@region_slug}/categories/lawyers"} class="btn btn-outline btn-sm text-white border-white/50 hover:bg-white hover:text-neutral hover:border-white">
                {gettext("Legal Help")}
              </.link>
              <.link navigate={~p"/#{@region_slug}/cities"} class="btn btn-ghost btn-sm text-white/80">
                {gettext("All Cities")}
                <span class="hero-arrow-right w-4 h-4"></span>
              </.link>
            </div>
          </div>
        </div>
      </section>

      <%!-- Stats Bar --%>
      <div class="bg-primary text-primary-content">
        <div class="container mx-auto px-4">
          <div class="stats stats-horizontal w-full bg-transparent text-primary-content">
            <div class="stat place-items-center py-6">
              <div class="stat-value">{@total_businesses}+</div>
              <div class="stat-desc text-primary-content/80">{gettext("Local Businesses")}</div>
            </div>
            <div class="stat place-items-center py-6">
              <div class="stat-value">{@local_gems_count}</div>
              <div class="stat-desc text-primary-content/80">{gettext("Authentic Local Gems")}</div>
            </div>
            <div class="stat place-items-center py-6">
              <div class="stat-value">{@cities_count}</div>
              <div class="stat-desc text-primary-content/80">{gettext("Cities")}</div>
            </div>
          </div>
        </div>
      </div>

      <%!-- Phrase Banner --%>
      <%= if @phrase do %>
        <div class="bg-base-200 border-b border-base-300">
          <div class="container mx-auto px-4 py-4">
            <div class="flex flex-wrap items-center justify-center gap-x-6 gap-y-2">
              <span class="badge badge-neutral badge-sm">{gettext("Learn the language")}</span>
              <div class="flex items-center gap-3">
                <span class="text-xl font-semibold text-primary">"{@phrase["local"]}"</span>
                <span class="text-base-content/50">=</span>
                <span class="text-base-content">{Gettext.gettext(GaliciaLocalWeb.Gettext, @phrase["english"])}</span>
              </div>
              <span class="text-sm text-base-content/60 italic">{Gettext.gettext(GaliciaLocalWeb.Gettext, @phrase["usage"])}</span>
              <button phx-click="new_phrase" class="btn btn-ghost btn-xs">
                <span class="hero-arrow-path w-4 h-4"></span>
                {gettext("Another")}
              </button>
            </div>
          </div>
        </div>
      <% end %>

      <%!-- Featured Cities --%>
      <section class="py-16 px-4">
        <div class="container mx-auto max-w-7xl">
          <div class="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 mb-10">
            <div>
              <h2 class="text-3xl font-bold">{gettext("Explore %{region}", region: @region_name)}</h2>
              <p class="text-base-content/70 mt-2">{gettext("Each city has its own character and charm")}</p>
            </div>
            <.link navigate={~p"/#{@region_slug}/cities"} class="btn btn-ghost btn-sm">
              {gettext("View all cities")}
              <span class="hero-arrow-right w-4 h-4"></span>
            </.link>
          </div>

          <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6">
            <%= for city <- @featured_cities do %>
              <.link navigate={~p"/#{@region_slug}/cities/#{city.slug}"} class="group">
                <div class="card card-compact bg-base-100 shadow-md hover:shadow-xl transition-all duration-300 overflow-hidden">
                  <figure class="relative aspect-[4/3]">
                    <img
                      src={city.image_url || "https://images.unsplash.com/photo-1558618666-fcd25c85cd64?w=400"}
                      alt={city.name}
                      class="w-full h-full object-cover group-hover:scale-105 transition-transform duration-500"
                    />
                    <div class="absolute inset-0 bg-gradient-to-t from-black/70 via-black/20 to-transparent"></div>
                    <div class="absolute bottom-0 left-0 right-0 p-4">
                      <h3 class="text-xl font-bold text-white">{city.name}</h3>
                      <p class="text-white/80 text-sm">{city.province}</p>
                    </div>
                  </figure>
                  <div class="card-body">
                    <p class="text-sm text-base-content/70 line-clamp-2">{localized(city, :description, @locale)}</p>
                    <div class="card-actions justify-between items-center mt-2">
                      <div class="badge badge-ghost">{ngettext("%{count} listing", "%{count} listings", city.business_count || 0)}</div>
                      <span class="text-primary text-sm font-medium group-hover:underline">{gettext("Explore")}</span>
                    </div>
                  </div>
                </div>
              </.link>
            <% end %>
          </div>
        </div>
      </section>

      <%!-- Cultural Tips --%>
      <%= if @cultural_tips != [] do %>
        <section class="py-16 px-4 bg-base-200">
          <div class="container mx-auto max-w-7xl">
            <div class="text-center mb-12">
              <h2 class="text-3xl font-bold">{gettext("Living Like a Local")}</h2>
              <p class="text-base-content/70 mt-2 max-w-2xl mx-auto">
                {gettext("Small things that make a big difference when integrating into local life")}
              </p>
            </div>

            <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
              <%= for tip <- @cultural_tips do %>
                <div class="card bg-base-100 shadow-sm hover:shadow-md transition-shadow">
                  <div class="card-body">
                    <div class="flex items-start gap-4">
                      <div class="flex-shrink-0 w-12 h-12 rounded-xl bg-primary/10 flex items-center justify-center">
                        <.dynamic_icon name={tip["icon"] || "sparkles"} class="w-6 h-6 text-primary" />
                      </div>
                      <div>
                        <h3 class="card-title text-lg">{Gettext.gettext(GaliciaLocalWeb.Gettext, tip["title"])}</h3>
                        <p class="text-base-content/70 mt-1">{Gettext.gettext(GaliciaLocalWeb.Gettext, tip["tip"])}</p>
                      </div>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        </section>
      <% end %>

      <%!-- Categories --%>
      <section class="py-16 px-4">
        <div class="container mx-auto max-w-7xl">
          <div class="text-center mb-12">
            <h2 class="text-3xl font-bold">{gettext("Browse by Category")}</h2>
            <p class="text-base-content/70 mt-2">{gettext("Find exactly what you need")}</p>
          </div>

          <%= for {priority, categories} <- @categories_by_priority do %>
            <div class="mb-10">
              <h3 class="text-lg font-semibold mb-4 flex items-center gap-2">
                <span class={"badge #{priority_badge_class(priority)}"}>{priority_label(priority)}</span>
              </h3>
              <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6 gap-4">
                <%= for category <- categories do %>
                  <.link
                    navigate={~p"/#{@region_slug}/categories/#{category.slug}"}
                    class="group card bg-base-100 shadow-md hover:shadow-xl hover:-translate-y-1 transition-all"
                  >
                    <div class="card-body items-center text-center p-4">
                      <div class={"w-12 h-12 rounded-full flex items-center justify-center mb-2 #{priority_bg_class(priority)} group-hover:scale-110 transition-transform"}>
                        <.dynamic_icon name={category.icon || "building-storefront"} class="w-6 h-6" />
                      </div>
                      <% primary = localized_name(category, @locale) %>
                      <% secondary = if @secondary_locale, do: localized_name(category, @secondary_locale), else: nil %>
                      <span class="font-medium text-sm">{primary}</span>
                      <%= if secondary && secondary != primary do %>
                        <span class="text-xs text-base-content/60">{secondary}</span>
                      <% end %>
                    </div>
                  </.link>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      </section>

      <%!-- Recent Businesses --%>
      <%= if length(@recent_businesses) > 0 do %>
        <section class="py-16 px-4 bg-base-200">
          <div class="container mx-auto max-w-7xl">
            <div class="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 mb-10">
              <div>
                <h2 class="text-3xl font-bold">{gettext("Recently Added")}</h2>
                <p class="text-base-content/70 mt-2">{gettext("Fresh additions to help you explore")}</p>
              </div>
            </div>

            <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
              <%= for business <- @recent_businesses do %>
                <.business_card business={business} locale={@locale} region_slug={@region_slug} />
              <% end %>
            </div>
          </div>
        </section>
      <% end %>

      <%!-- CTA Section --%>
      <section class="py-20 px-4 bg-neutral text-neutral-content">
        <div class="container mx-auto max-w-4xl text-center">
          <h2 class="text-3xl md:text-4xl font-bold mb-4">{gettext("Ready to Become Part of %{region}?", region: @region_name)}</h2>
          <p class="text-lg opacity-90 mb-8 max-w-2xl mx-auto">
            {gettext("Skip the tourist traps. Find the places locals actually go. Learn the customs that earn respect. Make real connections.")}
          </p>
          <div class="flex flex-wrap justify-center gap-4">
            <.link navigate={~p"/#{@region_slug}/search?filter=local-gems"} class="btn btn-primary btn-lg">
              <span class="hero-star w-5 h-5"></span>
              {gettext("Discover Local Gems")}
            </.link>
            <.link navigate={~p"/#{@region_slug}/cities"} class="btn btn-outline btn-lg text-neutral-content border-neutral-content/50 hover:bg-neutral-content hover:text-neutral">
              {gettext("Explore Cities")}
            </.link>
          </div>
        </div>
      </section>

      <%!-- Footer --%>
      <footer class="footer footer-center p-10 bg-base-200 text-base-content">
        <aside>
          <p class="font-bold text-lg">StartLocal</p>
          <p class="text-base-content/70">{gettext("Helping newcomers feel at home")}</p>
        </aside>
        <nav class="grid grid-flow-col gap-6">
          <.link navigate={~p"/about"} class="link link-hover">{gettext("About")}</.link>
          <.link navigate={~p"/contact"} class="link link-hover">{gettext("Contact")}</.link>
          <.link navigate={~p"/privacy"} class="link link-hover">{gettext("Privacy")}</.link>
        </nav>
        <aside>
          <p class="text-sm text-base-content/50">&copy; 2026 StartLocal. Made with love for newcomers worldwide.</p>
        </aside>
      </footer>
    </div>
    """
  end

  # Helper Components

  attr :business, :map, required: true
  attr :locale, :string, default: "en"
  attr :region_slug, :string, required: true
  defp business_card(assigns) do
    ~H"""
    <.link navigate={~p"/#{@region_slug}/businesses/#{@business.id}"} class="group">
      <div class="card bg-base-100 shadow-sm hover:shadow-lg transition-all duration-300">
        <div class="card-body">
          <div class="flex justify-between items-start">
            <div class="flex-1">
              <h3 class="card-title text-lg group-hover:text-primary transition-colors">
                {@business.name}
              </h3>
              <p class="text-sm text-base-content/60 mt-1">
                {@business.city.name} &middot; {localized_name(@business.category, @locale)}
              </p>
            </div>
            <div class="flex gap-2">
              <%= if @business.local_gem_score && Decimal.compare(@business.local_gem_score, Decimal.new("0.7")) == :gt do %>
                <div class="tooltip" data-tip="Local Gem">
                  <div class="badge badge-warning gap-1">
                    <span class="hero-star-solid w-3 h-3"></span>
                  </div>
                </div>
              <% end %>
              <%= if @business.speaks_english do %>
                <div class="tooltip" data-tip="English spoken">
                  <div class="badge badge-info">EN</div>
                </div>
              <% end %>
            </div>
          </div>

          <p class="text-sm text-base-content/70 line-clamp-2 mt-3">
            {localized(@business, :summary, @locale) || localized(@business, :description, @locale)}
          </p>

          <div class="flex items-center justify-between mt-4 pt-4 border-t border-base-200">
            <%= if @business.rating do %>
              <div class="flex items-center gap-1">
                <span class="text-warning">&#9733;</span>
                <span class="font-medium">{Decimal.round(@business.rating, 1)}</span>
                <span class="text-xs text-base-content/50">({ngettext("%{count} review", "%{count} reviews", @business.review_count)})</span>
              </div>
            <% else %>
              <span class="text-sm text-base-content/50">{gettext("No reviews yet")}</span>
            <% end %>
            <%= if @business.newcomer_friendly_score do %>
              <span class="text-xs text-base-content/60">
                <%= cond do %>
                  <% Decimal.compare(@business.newcomer_friendly_score, Decimal.new("0.7")) == :gt -> %>
                    {gettext("Easy for newcomers")}
                  <% Decimal.compare(@business.newcomer_friendly_score, Decimal.new("0.4")) == :gt -> %>
                    {gettext("Some local language helpful")}
                  <% true -> %>
                    {gettext("Bring a local friend!")}
                <% end %>
              </span>
            <% end %>
          </div>
        </div>
      </div>
    </.link>
    """
  end

  attr :name, :string, required: true
  attr :class, :string, default: "w-6 h-6"
  defp dynamic_icon(assigns) do
    ~H"""
    <span class={"hero-#{@name} #{@class}"}></span>
    """
  end

  defp priority_label(1), do: gettext("Getting Started")
  defp priority_label(2), do: gettext("Daily Life")
  defp priority_label(3), do: gettext("Culture & Leisure")
  defp priority_label(4), do: gettext("Practical Services")
  defp priority_label(_), do: gettext("Other")

  defp priority_badge_class(1), do: "badge-primary"
  defp priority_badge_class(2), do: "badge-secondary"
  defp priority_badge_class(3), do: "badge-accent"
  defp priority_badge_class(4), do: "badge-neutral"
  defp priority_badge_class(_), do: "badge-ghost"

  defp priority_bg_class(1), do: "bg-primary/10 text-primary"
  defp priority_bg_class(2), do: "bg-secondary/10 text-secondary"
  defp priority_bg_class(3), do: "bg-accent/10 text-accent"
  defp priority_bg_class(4), do: "bg-neutral/10 text-neutral"
  defp priority_bg_class(_), do: "bg-base-200"
end
