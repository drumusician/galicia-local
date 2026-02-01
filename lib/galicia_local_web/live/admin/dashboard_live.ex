defmodule GaliciaLocalWeb.Admin.DashboardLive do
  @moduledoc """
  Main admin dashboard for GaliciaLocal.
  Provides overview and navigation to all admin functions.
  """
  use GaliciaLocalWeb, :live_view

  alias GaliciaLocal.Directory.{City, Category, Business}
  alias GaliciaLocal.Community.Suggestion

  @impl true
  def mount(_params, _session, socket) do
    stats = load_stats(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, gettext("Admin Dashboard"))
     |> assign(:stats, stats)}
  end

  defp load_stats(actor) do
    businesses = Business.list!()
    cities = City.list!()
    categories = Category.list!()
    pending_suggestions = Suggestion.list_pending!(actor: actor)

    %{
      total_businesses: length(businesses),
      pending_enrichment: Enum.count(businesses, &(&1.status == :pending)),
      enriched: Enum.count(businesses, &(&1.status == :enriched)),
      english_speaking: Enum.count(businesses, &(&1.speaks_english == true)),
      total_cities: length(cities),
      total_categories: length(categories),
      recent_businesses: businesses
                         |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
                         |> Enum.take(5),
      pending_suggestions: pending_suggestions
    }
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200">
      <!-- Admin Header -->
      <header class="bg-base-100 border-b border-base-300 sticky top-0 z-50">
        <div class="container mx-auto px-6 py-4">
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-4">
              <h1 class="text-2xl font-bold text-primary">
                <span class="hero-cog-6-tooth w-7 h-7 inline-block mr-2"></span>
                {gettext("Admin Dashboard")}
              </h1>
            </div>
            <div class="flex items-center gap-4">
              <span class="text-sm text-base-content/70">
                {gettext("Logged in as")} <strong>{@current_user.email}</strong>
              </span>
              <.link navigate={~p"/"} class="btn btn-ghost btn-sm">
                <span class="hero-home w-4 h-4"></span>
                {gettext("View Site")}
              </.link>
              <.link href={~p"/sign-out"} class="btn btn-ghost btn-sm">
                <span class="hero-arrow-right-on-rectangle w-4 h-4"></span>
                {gettext("Sign Out")}
              </.link>
            </div>
          </div>
        </div>
      </header>

      <main class="container mx-auto px-6 py-8">
        <!-- Stats Overview -->
        <div class="stats stats-vertical lg:stats-horizontal shadow w-full mb-8">
          <div class="stat">
            <div class="stat-figure text-primary">
              <span class="hero-building-storefront w-8 h-8"></span>
            </div>
            <div class="stat-title">{gettext("Total Businesses")}</div>
            <div class="stat-value text-primary">{@stats.total_businesses}</div>
            <div class="stat-desc">{ngettext("%{count} enriched", "%{count} enriched", @stats.enriched)}</div>
          </div>

          <div class="stat">
            <div class="stat-figure text-warning">
              <span class="hero-clock w-8 h-8"></span>
            </div>
            <div class="stat-title">{gettext("Pending Enrichment")}</div>
            <div class="stat-value text-warning">{@stats.pending_enrichment}</div>
            <div class="stat-desc">{gettext("Awaiting LLM processing")}</div>
          </div>

          <div class="stat">
            <div class="stat-figure text-success">
              <span class="hero-language w-8 h-8"></span>
            </div>
            <div class="stat-title">{gettext("English Speaking")}</div>
            <div class="stat-value text-success">{@stats.english_speaking}</div>
            <div class="stat-desc">{gettext("Detected from reviews")}</div>
          </div>

          <div class="stat">
            <div class="stat-figure text-secondary">
              <span class="hero-map-pin w-8 h-8"></span>
            </div>
            <div class="stat-title">{gettext("Cities")}</div>
            <div class="stat-value text-secondary">{@stats.total_cities}</div>
            <div class="stat-desc">{ngettext("%{count} category", "%{count} categories", @stats.total_categories)}</div>
          </div>
        </div>

        <!-- Admin Navigation Cards -->
        <h2 class="text-xl font-bold mb-4">{gettext("Admin Tools")}</h2>
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6 mb-8">
          <!-- Scraper -->
          <.link navigate={~p"/admin/scraper"} class="card bg-base-100 shadow-xl hover:shadow-2xl transition-shadow">
            <div class="card-body">
              <div class="flex items-center gap-4">
                <div class="bg-primary/10 rounded-xl p-3">
                  <span class="hero-magnifying-glass-circle w-8 h-8 text-primary"></span>
                </div>
                <div>
                  <h3 class="card-title">{gettext("Scraper")}</h3>
                  <p class="text-sm text-base-content/70">{gettext("Import businesses from Google Places")}</p>
                </div>
              </div>
            </div>
          </.link>

          <!-- Businesses -->
          <.link navigate={~p"/admin/businesses"} class="card bg-base-100 shadow-xl hover:shadow-2xl transition-shadow">
            <div class="card-body">
              <div class="flex items-center gap-4">
                <div class="bg-secondary/10 rounded-xl p-3">
                  <span class="hero-building-storefront w-8 h-8 text-secondary"></span>
                </div>
                <div>
                  <h3 class="card-title">{gettext("Businesses")}</h3>
                  <p class="text-sm text-base-content/70">{gettext("Manage all business listings")}</p>
                </div>
              </div>
            </div>
          </.link>

          <!-- Cities -->
          <.link navigate={~p"/admin/cities"} class="card bg-base-100 shadow-xl hover:shadow-2xl transition-shadow">
            <div class="card-body">
              <div class="flex items-center gap-4">
                <div class="bg-accent/10 rounded-xl p-3">
                  <span class="hero-map-pin w-8 h-8 text-accent"></span>
                </div>
                <div>
                  <h3 class="card-title">{gettext("Cities")}</h3>
                  <p class="text-sm text-base-content/70">{gettext("Manage city listings")}</p>
                </div>
              </div>
            </div>
          </.link>

          <!-- Categories -->
          <.link navigate={~p"/admin/categories"} class="card bg-base-100 shadow-xl hover:shadow-2xl transition-shadow">
            <div class="card-body">
              <div class="flex items-center gap-4">
                <div class="bg-info/10 rounded-xl p-3">
                  <span class="hero-squares-2x2 w-8 h-8 text-info"></span>
                </div>
                <div>
                  <h3 class="card-title">{gettext("Categories")}</h3>
                  <p class="text-sm text-base-content/70">{gettext("Manage business categories")}</p>
                </div>
              </div>
            </div>
          </.link>

          <!-- Analytics -->
          <.link navigate={~p"/admin/analytics"} class="card bg-base-100 shadow-xl hover:shadow-2xl transition-shadow">
            <div class="card-body">
              <div class="flex items-center gap-4">
                <div class="bg-success/10 rounded-xl p-3">
                  <span class="hero-chart-bar w-8 h-8 text-success"></span>
                </div>
                <div>
                  <h3 class="card-title">{gettext("Analytics")}</h3>
                  <p class="text-sm text-base-content/70">{gettext("Page views and traffic")}</p>
                </div>
              </div>
            </div>
          </.link>

          <!-- Business Claims -->
          <.link navigate={~p"/admin/claims"} class="card bg-base-100 shadow-xl hover:shadow-2xl transition-shadow">
            <div class="card-body">
              <div class="flex items-center gap-4">
                <div class="bg-warning/10 rounded-xl p-3">
                  <span class="hero-shield-check w-8 h-8 text-warning"></span>
                </div>
                <div>
                  <h3 class="card-title">{gettext("Business Claims")}</h3>
                  <p class="text-sm text-base-content/70">{gettext("Review ownership claims")}</p>
                </div>
              </div>
            </div>
          </.link>

          <!-- Users -->
          <.link navigate={~p"/admin/users"} class="card bg-base-100 shadow-xl hover:shadow-2xl transition-shadow">
            <div class="card-body">
              <div class="flex items-center gap-4">
                <div class="bg-error/10 rounded-xl p-3">
                  <span class="hero-users w-8 h-8 text-error"></span>
                </div>
                <div>
                  <h3 class="card-title">{gettext("Users")}</h3>
                  <p class="text-sm text-base-content/70">{gettext("View and manage users")}</p>
                </div>
              </div>
            </div>
          </.link>

          <!-- Oban Dashboard -->
          <a href="/admin/oban" target="_blank" class="card bg-base-100 shadow-xl hover:shadow-2xl transition-shadow">
            <div class="card-body">
              <div class="flex items-center gap-4">
                <div class="bg-warning/10 rounded-xl p-3">
                  <span class="hero-queue-list w-8 h-8 text-warning"></span>
                </div>
                <div>
                  <h3 class="card-title">
                    {gettext("Job Queue")}
                    <span class="hero-arrow-top-right-on-square w-4 h-4 text-base-content/50"></span>
                  </h3>
                  <p class="text-sm text-base-content/70">{gettext("Oban job dashboard")}</p>
                </div>
              </div>
            </div>
          </a>

          <!-- Phoenix Dashboard -->
          <a href="/admin/dashboard" target="_blank" class="card bg-base-100 shadow-xl hover:shadow-2xl transition-shadow">
            <div class="card-body">
              <div class="flex items-center gap-4">
                <div class="bg-error/10 rounded-xl p-3">
                  <span class="hero-chart-bar w-8 h-8 text-error"></span>
                </div>
                <div>
                  <h3 class="card-title">
                    {gettext("Phoenix Dashboard")}
                    <span class="hero-arrow-top-right-on-square w-4 h-4 text-base-content/50"></span>
                  </h3>
                  <p class="text-sm text-base-content/70">{gettext("System metrics & performance")}</p>
                </div>
              </div>
            </div>
          </a>
        </div>

        <!-- Recent Businesses -->
        <div class="card bg-base-100 shadow-xl">
          <div class="card-body">
            <h2 class="card-title">
              <span class="hero-clock w-6 h-6"></span>
              {gettext("Recently Added Businesses")}
            </h2>

            <%= if length(@stats.recent_businesses) > 0 do %>
              <div class="overflow-x-auto">
                <table class="table table-sm">
                  <thead>
                    <tr>
                      <th>{gettext("Name")}</th>
                      <th>{gettext("Status")}</th>
                      <th>{gettext("Rating")}</th>
                      <th>{gettext("Added")}</th>
                      <th></th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for business <- @stats.recent_businesses do %>
                      <tr>
                        <td class="font-medium">{business.name}</td>
                        <td>
                          <span class={["badge badge-sm", status_badge_class(business.status)]}>
                            {business.status}
                          </span>
                        </td>
                        <td>
                          <%= if business.rating do %>
                            <div class="flex items-center gap-1">
                              <span class="text-warning">★</span>
                              {Decimal.round(business.rating, 1)}
                            </div>
                          <% else %>
                            <span class="text-base-content/50">-</span>
                          <% end %>
                        </td>
                        <td class="text-sm text-base-content/60">
                          {Calendar.strftime(business.inserted_at, "%b %d, %H:%M")}
                        </td>
                        <td>
                          <.link navigate={~p"/businesses/#{business.id}"} class="btn btn-ghost btn-xs">
                            {gettext("View")}
                          </.link>
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            <% else %>
              <div class="text-center py-8 text-base-content/50">
                <span class="hero-inbox w-12 h-12 mx-auto mb-2"></span>
                <p>{gettext("No businesses yet. Start by importing some from the Scraper.")}</p>
              </div>
            <% end %>
          </div>
        </div>
        <!-- Pending Suggestions -->
        <div class="card bg-base-100 shadow-xl mt-6">
          <div class="card-body">
            <h2 class="card-title">
              <span class="hero-light-bulb w-6 h-6"></span>
              {gettext("Pending Suggestions")}
              <%= if length(@stats.pending_suggestions) > 0 do %>
                <span class="badge badge-warning">{length(@stats.pending_suggestions)}</span>
              <% end %>
            </h2>

            <%= if length(@stats.pending_suggestions) > 0 do %>
              <div class="overflow-x-auto">
                <table class="table table-sm">
                  <thead>
                    <tr>
                      <th>{gettext("Business Name")}</th>
                      <th>{gettext("City")}</th>
                      <th>{gettext("Reason")}</th>
                      <th>{gettext("Submitted")}</th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for suggestion <- @stats.pending_suggestions do %>
                      <tr>
                        <td class="font-medium">{suggestion.business_name}</td>
                        <td class="text-sm">{suggestion.city_name}</td>
                        <td class="text-sm max-w-xs truncate">{suggestion.reason || "-"}</td>
                        <td class="text-sm text-base-content/60">
                          {Calendar.strftime(suggestion.inserted_at, "%b %d, %H:%M")}
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            <% else %>
              <div class="text-center py-8 text-base-content/50">
                <p>{gettext("No pending suggestions.")}</p>
              </div>
            <% end %>
          </div>
        </div>
      </main>
    </div>
    """
  end

  defp status_badge_class(:pending), do: "badge-warning"
  defp status_badge_class(:enriched), do: "badge-success"
  defp status_badge_class(:verified), do: "badge-info"
  defp status_badge_class(:failed), do: "badge-error"
  defp status_badge_class(_), do: "badge-ghost"
end
