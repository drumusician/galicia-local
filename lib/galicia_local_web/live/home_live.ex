defmodule GaliciaLocalWeb.HomeLive do
  @moduledoc """
  Home page LiveView for GaliciaLocal.
  Helping newcomers integrate into Galician life, not isolate from it.
  """
  use GaliciaLocalWeb, :live_view

  require Ash.Query

  alias GaliciaLocal.Directory.{City, Category, Business}

  # Galician phrases - verified from omniglot.com and galegoway.com
  @galician_phrases [
    %{galician: "Bos días", spanish: "Buenos días", english: "Good morning", usage: "Morning greeting until ~2pm"},
    %{galician: "Boas tardes", spanish: "Buenas tardes", english: "Good afternoon", usage: "Afternoon greeting 2pm-8pm"},
    %{galician: "Boas noites", spanish: "Buenas noches", english: "Good evening", usage: "Evening greeting after 8pm"},
    %{galician: "Moitas grazas", spanish: "Muchas gracias", english: "Thank you very much", usage: "Showing appreciation"},
    %{galician: "Por favor", spanish: "Por favor", english: "Please", usage: "Being polite"},
    %{galician: "Ata logo", spanish: "Hasta luego", english: "See you later", usage: "Casual goodbye"},
    %{galician: "Bo proveito", spanish: "Buen provecho", english: "Enjoy your meal", usage: "Said before eating"},
    %{galician: "Saúde!", spanish: "¡Salud!", english: "Cheers!", usage: "Toast when drinking"}
  ]

  # Cultural tips to show
  @cultural_tips [
    %{title: "The Siesta is Real", tip: "Many shops close 2-5pm. Plan errands for mornings or evenings.", icon: "clock"},
    %{title: "Lunch is the Main Meal", tip: "Galicians eat lunch 2-4pm. Restaurants are empty at noon.", icon: "sun"},
    %{title: "Free Tapas Culture", tip: "In many bars, tapas come free with drinks. Just order a caña!", icon: "sparkles"},
    %{title: "Cash is King", tip: "Smaller shops often prefer cash. Always have some euros handy.", icon: "banknotes"},
    %{title: "Greet Everyone", tip: "Say 'Bos días' when entering shops. It's expected and appreciated.", icon: "hand-raised"},
    %{title: "Thermal Springs", tip: "Ourense has free public hot springs. Bring a towel and join the locals!", icon: "fire"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    featured_cities =
      City.featured!()
      |> Ash.load!([:business_count])

    categories_by_priority =
      Category.list!()
      |> Enum.group_by(& &1.priority)
      |> Enum.sort_by(fn {priority, _} -> priority end)

    recent_businesses =
      Business.recent!()
      |> Ash.load!([:city, :category])

    # Get some stats
    total_businesses = Ash.count!(Business)

    local_gems_count =
      Business
      |> Ash.Query.filter(local_gem_score > 0.7 and status in [:enriched, :verified])
      |> Ash.count!()

    cities_count = Ash.count!(City)

    # Pick a random phrase and tips to display
    random_phrase = Enum.random(@galician_phrases)
    random_tips = Enum.take_random(@cultural_tips, 3)

    {:ok,
     socket
     |> assign(:page_title, "Integrate into Galician Life")
     |> assign(:featured_cities, featured_cities)
     |> assign(:categories_by_priority, categories_by_priority)
     |> assign(:recent_businesses, recent_businesses)
     |> assign(:total_businesses, total_businesses)
     |> assign(:local_gems_count, local_gems_count)
     |> assign(:cities_count, cities_count)
     |> assign(:galician_phrase, random_phrase)
     |> assign(:cultural_tips, random_tips)
     |> assign(:search_query, "")}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    if String.trim(query) != "" do
      {:noreply, push_navigate(socket, to: ~p"/search?q=#{query}")}
    else
      {:noreply, socket}
    end
  end

  def handle_event("new_phrase", _, socket) do
    {:noreply, assign(socket, :galician_phrase, Enum.random(@galician_phrases))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen">
      <%!-- Hero Section --%>
      <section class="hero min-h-[80vh] relative">
        <div
          class="absolute inset-0 bg-cover bg-center"
          style="background-image: url('https://images.unsplash.com/photo-1539037116277-4db20889f2d4?w=1920&q=80');"
        >
        </div>
        <div class="absolute inset-0 bg-black/50"></div>
        <div class="hero-content text-center text-neutral-content py-20">
          <div class="max-w-3xl">
            <p class="mb-4 text-lg opacity-90 tracking-wide uppercase">Welcome to Galicia</p>
            <h1 class="mb-6 text-5xl md:text-6xl lg:text-7xl font-bold leading-tight">
              Make Galicia<br/>Your Home
            </h1>
            <p class="mb-10 text-lg md:text-xl opacity-90 max-w-2xl mx-auto leading-relaxed">
              Discover local businesses, learn Galician customs, and truly integrate into your new community.
            </p>

            <%!-- Search --%>
            <form phx-submit="search" class="form-control w-full max-w-xl mx-auto mb-8">
              <div class="join w-full shadow-xl">
                <input
                  type="text"
                  name="query"
                  value={@search_query}
                  placeholder="Search for lawyers, restaurants, services..."
                  class="input input-lg join-item flex-1 bg-base-100 text-base-content focus:outline-none"
                />
                <button type="submit" class="btn btn-primary btn-lg join-item px-8">
                  <span class="hero-magnifying-glass w-5 h-5"></span>
                  <span class="hidden sm:inline">Search</span>
                </button>
              </div>
            </form>

            <%!-- Quick action buttons --%>
            <div class="flex flex-wrap justify-center gap-3">
              <.link navigate={~p"/search?filter=local-gems"} class="btn btn-outline btn-sm text-white border-white/50 hover:bg-white hover:text-neutral hover:border-white">
                <span class="hero-star w-4 h-4"></span>
                Local Gems
              </.link>
              <.link navigate={~p"/categories/restaurants"} class="btn btn-outline btn-sm text-white border-white/50 hover:bg-white hover:text-neutral hover:border-white">
                Restaurants
              </.link>
              <.link navigate={~p"/categories/lawyers"} class="btn btn-outline btn-sm text-white border-white/50 hover:bg-white hover:text-neutral hover:border-white">
                Legal Help
              </.link>
              <.link navigate={~p"/cities"} class="btn btn-ghost btn-sm text-white/80">
                All Cities
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
              <div class="stat-desc text-primary-content/80">Local Businesses</div>
            </div>
            <div class="stat place-items-center py-6">
              <div class="stat-value">{@local_gems_count}</div>
              <div class="stat-desc text-primary-content/80">Authentic Local Gems</div>
            </div>
            <div class="stat place-items-center py-6">
              <div class="stat-value">{@cities_count}</div>
              <div class="stat-desc text-primary-content/80">Galician Cities</div>
            </div>
          </div>
        </div>
      </div>

      <%!-- Galician Phrase Banner --%>
      <div class="bg-base-200 border-b border-base-300">
        <div class="container mx-auto px-4 py-4">
          <div class="flex flex-wrap items-center justify-center gap-x-6 gap-y-2">
            <span class="badge badge-neutral badge-sm">Learn Galician</span>
            <div class="flex items-center gap-3">
              <span class="text-xl font-semibold text-primary">"{@galician_phrase.galician}"</span>
              <span class="text-base-content/50">=</span>
              <span class="text-base-content">{@galician_phrase.english}</span>
            </div>
            <span class="text-sm text-base-content/60 italic">{@galician_phrase.usage}</span>
            <button phx-click="new_phrase" class="btn btn-ghost btn-xs">
              <span class="hero-arrow-path w-4 h-4"></span>
              Another
            </button>
          </div>
        </div>
      </div>

      <%!-- Featured Cities --%>
      <section class="py-16 px-4">
        <div class="container mx-auto max-w-7xl">
          <div class="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 mb-10">
            <div>
              <h2 class="text-3xl font-bold">Explore Galicia</h2>
              <p class="text-base-content/70 mt-2">Each city has its own character and charm</p>
            </div>
            <.link navigate={~p"/cities"} class="btn btn-ghost btn-sm">
              View all cities
              <span class="hero-arrow-right w-4 h-4"></span>
            </.link>
          </div>

          <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6">
            <%= for city <- @featured_cities do %>
              <.link navigate={~p"/cities/#{city.slug}"} class="group">
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
                    <p class="text-sm text-base-content/70 line-clamp-2">{city.description}</p>
                    <div class="card-actions justify-between items-center mt-2">
                      <div class="badge badge-ghost">{city.business_count || 0} listings</div>
                      <span class="text-primary text-sm font-medium group-hover:underline">Explore</span>
                    </div>
                  </div>
                </div>
              </.link>
            <% end %>
          </div>
        </div>
      </section>

      <%!-- Cultural Tips --%>
      <section class="py-16 px-4 bg-base-200">
        <div class="container mx-auto max-w-7xl">
          <div class="text-center mb-12">
            <h2 class="text-3xl font-bold">Living Like a Galician</h2>
            <p class="text-base-content/70 mt-2 max-w-2xl mx-auto">
              Small things that make a big difference when integrating into local life
            </p>
          </div>

          <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
            <%= for tip <- @cultural_tips do %>
              <div class="card bg-base-100 shadow-sm hover:shadow-md transition-shadow">
                <div class="card-body">
                  <div class="flex items-start gap-4">
                    <div class="flex-shrink-0 w-12 h-12 rounded-xl bg-primary/10 flex items-center justify-center">
                      <.dynamic_icon name={tip.icon} class="w-6 h-6 text-primary" />
                    </div>
                    <div>
                      <h3 class="card-title text-lg">{tip.title}</h3>
                      <p class="text-base-content/70 mt-1">{tip.tip}</p>
                    </div>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      </section>

      <%!-- Categories --%>
      <section class="py-16 px-4">
        <div class="container mx-auto max-w-7xl">
          <div class="text-center mb-12">
            <h2 class="text-3xl font-bold">Browse by Category</h2>
            <p class="text-base-content/70 mt-2">Find exactly what you need</p>
          </div>

          <%= for {priority, categories} <- @categories_by_priority do %>
            <div class="mb-10">
              <h3 class="text-lg font-semibold mb-4 flex items-center gap-2">
                <span class={"badge #{priority_badge_class(priority)}"}>{priority_label(priority)}</span>
              </h3>
              <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6 gap-4">
                <%= for category <- categories do %>
                  <.link
                    navigate={~p"/categories/#{category.slug}"}
                    class="group card bg-base-100 shadow-md hover:shadow-xl hover:-translate-y-1 transition-all"
                  >
                    <div class="card-body items-center text-center p-4">
                      <div class={"w-12 h-12 rounded-full flex items-center justify-center mb-2 #{priority_bg_class(priority)} group-hover:scale-110 transition-transform"}>
                        <.dynamic_icon name={category.icon || "building-storefront"} class="w-6 h-6" />
                      </div>
                      <span class="font-medium text-sm">{category.name}</span>
                      <span class="text-xs text-base-content/60">{category.name_es}</span>
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
                <h2 class="text-3xl font-bold">Recently Added</h2>
                <p class="text-base-content/70 mt-2">Fresh additions to help you explore</p>
              </div>
            </div>

            <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
              <%= for business <- @recent_businesses do %>
                <.business_card business={business} />
              <% end %>
            </div>
          </div>
        </section>
      <% end %>

      <%!-- CTA Section --%>
      <section class="py-20 px-4 bg-neutral text-neutral-content">
        <div class="container mx-auto max-w-4xl text-center">
          <h2 class="text-3xl md:text-4xl font-bold mb-4">Ready to Become Part of Galicia?</h2>
          <p class="text-lg opacity-90 mb-8 max-w-2xl mx-auto">
            Skip the tourist traps. Find the places locals actually go.
            Learn the customs that earn respect. Make real connections.
          </p>
          <div class="flex flex-wrap justify-center gap-4">
            <.link navigate={~p"/search?filter=local-gems"} class="btn btn-primary btn-lg">
              <span class="hero-star w-5 h-5"></span>
              Discover Local Gems
            </.link>
            <.link navigate={~p"/cities"} class="btn btn-outline btn-lg text-neutral-content border-neutral-content/50 hover:bg-neutral-content hover:text-neutral">
              Explore Cities
            </.link>
          </div>
        </div>
      </section>

      <%!-- Footer --%>
      <footer class="footer footer-center p-10 bg-base-200 text-base-content">
        <aside>
          <p class="font-bold text-lg">GaliciaLocal.com</p>
          <p class="text-base-content/70">Helping newcomers integrate into Galician life</p>
        </aside>
        <nav class="grid grid-flow-col gap-6">
          <.link navigate={~p"/about"} class="link link-hover">About</.link>
          <.link navigate={~p"/contact"} class="link link-hover">Contact</.link>
          <.link navigate={~p"/privacy"} class="link link-hover">Privacy</.link>
        </nav>
        <aside>
          <p class="text-sm text-base-content/50">© 2026 GaliciaLocal. Made with love for Galicia.</p>
        </aside>
      </footer>
    </div>
    """
  end

  # Helper Components

  attr :business, :map, required: true
  defp business_card(assigns) do
    ~H"""
    <.link navigate={~p"/businesses/#{@business.id}"} class="group">
      <div class="card bg-base-100 shadow-sm hover:shadow-lg transition-all duration-300">
        <div class="card-body">
          <div class="flex justify-between items-start">
            <div class="flex-1">
              <h3 class="card-title text-lg group-hover:text-primary transition-colors">
                {@business.name}
              </h3>
              <p class="text-sm text-base-content/60 mt-1">
                {@business.city.name} · {@business.category.name}
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
            {@business.summary || @business.description}
          </p>

          <div class="flex items-center justify-between mt-4 pt-4 border-t border-base-200">
            <%= if @business.rating do %>
              <div class="flex items-center gap-1">
                <span class="text-warning">★</span>
                <span class="font-medium">{Decimal.round(@business.rating, 1)}</span>
                <span class="text-xs text-base-content/50">({@business.review_count} reviews)</span>
              </div>
            <% else %>
              <span class="text-sm text-base-content/50">No reviews yet</span>
            <% end %>
            <%= if @business.newcomer_friendly_score do %>
              <span class="text-xs text-base-content/60">
                <%= cond do %>
                  <% Decimal.compare(@business.newcomer_friendly_score, Decimal.new("0.7")) == :gt -> %>
                    Easy for newcomers
                  <% Decimal.compare(@business.newcomer_friendly_score, Decimal.new("0.4")) == :gt -> %>
                    Basic Spanish helpful
                  <% true -> %>
                    Bring a local friend!
                <% end %>
              </span>
            <% end %>
          </div>
        </div>
      </div>
    </.link>
    """
  end

  # Dynamic icon helper
  attr :name, :string, required: true
  attr :class, :string, default: "w-6 h-6"
  defp dynamic_icon(assigns) do
    ~H"""
    <span class={"hero-#{@name} #{@class}"}></span>
    """
  end

  # Helper functions

  defp priority_label(1), do: "Getting Started"
  defp priority_label(2), do: "Daily Life"
  defp priority_label(3), do: "Culture & Leisure"
  defp priority_label(4), do: "Practical Services"
  defp priority_label(_), do: "Other"

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
