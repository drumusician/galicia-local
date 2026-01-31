defmodule GaliciaLocalWeb.Admin.AnalyticsLive do
  use GaliciaLocalWeb, :live_view

  alias GaliciaLocal.Analytics.Tracker
  alias GaliciaLocal.Directory.{Business, City, Category}

  @impl true
  def mount(_params, _session, socket) do
    days = 30
    summary = Tracker.summary(days)
    top_businesses = enrich_top("business", days, &load_business/1)
    top_cities = enrich_top("city", days, &load_city/1)
    top_categories = enrich_top("category", days, &load_category/1)

    {:ok,
     socket
     |> assign(:page_title, "Analytics")
     |> assign(:days, days)
     |> assign(:summary, summary)
     |> assign(:top_businesses, top_businesses)
     |> assign(:top_cities, top_cities)
     |> assign(:top_categories, top_categories)}
  end

  @impl true
  def handle_event("change_period", %{"days" => days_str}, socket) do
    days = String.to_integer(days_str)
    summary = Tracker.summary(days)
    top_businesses = enrich_top("business", days, &load_business/1)
    top_cities = enrich_top("city", days, &load_city/1)
    top_categories = enrich_top("category", days, &load_category/1)

    {:noreply,
     socket
     |> assign(:days, days)
     |> assign(:summary, summary)
     |> assign(:top_businesses, top_businesses)
     |> assign(:top_cities, top_cities)
     |> assign(:top_categories, top_categories)}
  end

  defp enrich_top(page_type, days, loader) do
    Tracker.top(page_type, days, 10)
    |> Enum.map(fn %{resource_id: id, views: views} ->
      case loader.(id) do
        {:ok, resource} -> %{resource: resource, views: views}
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp load_business(id), do: Business.get_by_id(id)
  defp load_city(id), do: City.get_by_id(id)
  defp load_category(id), do: Category.get_by_id(id)

  @impl true
  def render(assigns) do
    total_views = Enum.reduce(assigns.summary, 0, fn s, acc -> acc + s.total_views end)
    assigns = assign(assigns, :total_views, total_views)

    ~H"""
    <div class="min-h-screen bg-base-200">
      <div class="container mx-auto max-w-6xl px-4 py-8">
        <div class="flex items-center justify-between mb-8">
          <div>
            <h1 class="text-3xl font-bold flex items-center gap-3">
              <span class="hero-chart-bar w-8 h-8 text-primary"></span>
              Analytics
            </h1>
            <p class="text-base-content/60 mt-1">Page view statistics for your directory.</p>
          </div>
          <div class="flex items-center gap-2">
            <span class="text-sm text-base-content/60">Period:</span>
            <select phx-change="change_period" name="days" class="select select-bordered select-sm">
              <option value="7" selected={@days == 7}>Last 7 days</option>
              <option value="30" selected={@days == 30}>Last 30 days</option>
              <option value="90" selected={@days == 90}>Last 90 days</option>
              <option value="365" selected={@days == 365}>Last year</option>
            </select>
          </div>
        </div>

        <!-- Summary Cards -->
        <div class="grid grid-cols-2 md:grid-cols-4 gap-4 mb-8">
          <div class="stat bg-base-100 rounded-box shadow">
            <div class="stat-title">Total Views</div>
            <div class="stat-value text-primary">{@total_views}</div>
            <div class="stat-desc">Last {@days} days</div>
          </div>
          <%= for stat <- @summary do %>
            <div class="stat bg-base-100 rounded-box shadow">
              <div class="stat-title capitalize">{stat.page_type} views</div>
              <div class="stat-value text-lg">{stat.total_views}</div>
              <div class="stat-desc">{stat.unique_resources} unique</div>
            </div>
          <% end %>
        </div>

        <!-- Top Tables -->
        <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <!-- Top Businesses -->
          <div class="card bg-base-100 shadow">
            <div class="card-body">
              <h2 class="card-title text-lg">
                <span class="hero-building-storefront w-5 h-5 text-primary"></span>
                Top Businesses
              </h2>
              <%= if length(@top_businesses) > 0 do %>
                <div class="overflow-x-auto">
                  <table class="table table-sm">
                    <thead>
                      <tr>
                        <th>#</th>
                        <th>Business</th>
                        <th class="text-right">Views</th>
                      </tr>
                    </thead>
                    <tbody>
                      <%= for {item, idx} <- Enum.with_index(@top_businesses, 1) do %>
                        <tr>
                          <td class="text-base-content/40">{idx}</td>
                          <td>
                            <.link navigate={~p"/businesses/#{item.resource.id}"} class="hover:text-primary font-medium text-sm">
                              {item.resource.name}
                            </.link>
                          </td>
                          <td class="text-right font-mono">{item.views}</td>
                        </tr>
                      <% end %>
                    </tbody>
                  </table>
                </div>
              <% else %>
                <p class="text-base-content/40 text-sm py-4">No data yet</p>
              <% end %>
            </div>
          </div>

          <!-- Top Cities -->
          <div class="card bg-base-100 shadow">
            <div class="card-body">
              <h2 class="card-title text-lg">
                <span class="hero-map w-5 h-5 text-primary"></span>
                Top Cities
              </h2>
              <%= if length(@top_cities) > 0 do %>
                <div class="overflow-x-auto">
                  <table class="table table-sm">
                    <thead>
                      <tr>
                        <th>#</th>
                        <th>City</th>
                        <th class="text-right">Views</th>
                      </tr>
                    </thead>
                    <tbody>
                      <%= for {item, idx} <- Enum.with_index(@top_cities, 1) do %>
                        <tr>
                          <td class="text-base-content/40">{idx}</td>
                          <td>
                            <.link navigate={~p"/cities/#{item.resource.slug}"} class="hover:text-primary font-medium text-sm">
                              {item.resource.name}
                            </.link>
                          </td>
                          <td class="text-right font-mono">{item.views}</td>
                        </tr>
                      <% end %>
                    </tbody>
                  </table>
                </div>
              <% else %>
                <p class="text-base-content/40 text-sm py-4">No data yet</p>
              <% end %>
            </div>
          </div>

          <!-- Top Categories -->
          <div class="card bg-base-100 shadow">
            <div class="card-body">
              <h2 class="card-title text-lg">
                <span class="hero-squares-2x2 w-5 h-5 text-primary"></span>
                Top Categories
              </h2>
              <%= if length(@top_categories) > 0 do %>
                <div class="overflow-x-auto">
                  <table class="table table-sm">
                    <thead>
                      <tr>
                        <th>#</th>
                        <th>Category</th>
                        <th class="text-right">Views</th>
                      </tr>
                    </thead>
                    <tbody>
                      <%= for {item, idx} <- Enum.with_index(@top_categories, 1) do %>
                        <tr>
                          <td class="text-base-content/40">{idx}</td>
                          <td>
                            <.link navigate={~p"/categories/#{item.resource.slug}"} class="hover:text-primary font-medium text-sm">
                              {item.resource.name}
                            </.link>
                          </td>
                          <td class="text-right font-mono">{item.views}</td>
                        </tr>
                      <% end %>
                    </tbody>
                  </table>
                </div>
              <% else %>
                <p class="text-base-content/40 text-sm py-4">No data yet</p>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
