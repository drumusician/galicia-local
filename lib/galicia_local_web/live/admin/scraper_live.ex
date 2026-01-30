defmodule GaliciaLocalWeb.Admin.ScraperLive do
  @moduledoc """
  Admin interface for managing web scraping operations.
  Supports both Google Places API and Crawly spiders.
  """
  use GaliciaLocalWeb, :live_view

  alias GaliciaLocal.Directory.{City, Category, Business, ScrapeJob}
  alias GaliciaLocal.Scraper

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      :timer.send_interval(3000, self(), :refresh_status)
    end

    cities = City.list!() |> Enum.sort_by(& &1.name)
    categories = Category.list!() |> Enum.sort_by(& &1.priority)
    recent_jobs = load_recent_jobs()
    spider_status = Scraper.status()
    oban_jobs = Scraper.job_status()

    {:ok,
     socket
     |> assign(:page_title, "Scraper Admin")
     |> assign(:cities, cities)
     |> assign(:categories, categories)
     |> assign(:recent_jobs, recent_jobs)
     |> assign(:spider_status, spider_status)
     |> assign(:oban_jobs, oban_jobs)
     |> assign(:selected_city, nil)
     |> assign(:selected_category, nil)
     |> assign(:scrape_source, "google_places")
     |> assign(:scraping, false)
     |> assign(:message, nil)}
  end

  @impl true
  def handle_info(:refresh_status, socket) do
    spider_status = Scraper.status()
    recent_jobs = load_recent_jobs()
    oban_jobs = Scraper.job_status()

    {:noreply,
     socket
     |> assign(:spider_status, spider_status)
     |> assign(:recent_jobs, recent_jobs)
     |> assign(:oban_jobs, oban_jobs)
     |> assign(:scraping, map_size(spider_status) > 0 || length(oban_jobs) > 0)}
  end

  @impl true
  def handle_event("form_change", params, socket) do
    city_id = params["city"] || ""
    category_id = params["category"] || ""
    source = params["source"] || socket.assigns.scrape_source

    selected_city = if city_id == "", do: nil, else: City.get_by_id!(city_id)
    selected_category = if category_id == "", do: nil, else: Category.get_by_id!(category_id)

    {:noreply,
     socket
     |> assign(:selected_city, selected_city)
     |> assign(:selected_category, selected_category)
     |> assign(:scrape_source, source)}
  end

  @impl true
  def handle_event("start_scrape", _params, socket) do
    city = socket.assigns.selected_city
    category = socket.assigns.selected_category
    source = socket.assigns.scrape_source

    cond do
      is_nil(city) ->
        {:noreply, assign(socket, :message, {:error, "Please select a city"})}

      is_nil(category) ->
        {:noreply, assign(socket, :message, {:error, "Please select a category"})}

      true ->
        result =
          case source do
            "google_places" ->
              Scraper.search_google_places(city, category)

            "paginas_amarillas" ->
              Scraper.scrape_city_category(city, category, :paginas_amarillas)
          end

        case result do
          {:ok, _} ->
            {:noreply,
             socket
             |> assign(:scraping, true)
             |> assign(:message, {:success, "Started #{source} search for #{category.name} in #{city.name}"})}

          {:error, :already_running} ->
            {:noreply, assign(socket, :message, {:warning, "Already running"})}

          {:error, reason} ->
            {:noreply, assign(socket, :message, {:error, "Failed: #{inspect(reason)}"})}
        end
    end
  end

  @impl true
  def handle_event("scrape_all_city", _params, socket) do
    city = socket.assigns.selected_city

    if is_nil(city) do
      {:noreply, assign(socket, :message, {:error, "Please select a city"})}
    else
      {:ok, jobs} = Scraper.search_google_places_city(city)

      {:noreply,
       socket
       |> assign(:scraping, true)
       |> assign(:message, {:success, "Queued #{length(jobs)} category searches for #{city.name}"})}
    end
  end

  @impl true
  def handle_event("stop_all", _params, socket) do
    Scraper.stop_all()
    {:noreply,
     socket
     |> assign(:scraping, false)
     |> assign(:message, {:success, "Stopped all spiders"})}
  end

  @impl true
  def handle_event("dismiss_message", _params, socket) do
    {:noreply, assign(socket, :message, nil)}
  end

  defp load_recent_jobs do
    ScrapeJob.list!()
    |> Ash.load!([:city, :category])
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
    |> Enum.take(10)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-100 p-6">
      <div class="container mx-auto max-w-6xl">
        <div class="flex items-center gap-4 mb-8">
          <.link navigate={~p"/admin"} class="btn btn-ghost btn-sm btn-circle">
            <span class="hero-arrow-left w-5 h-5"></span>
          </.link>
          <div>
            <h1 class="text-3xl font-bold text-base-content">Scraper Admin</h1>
            <p class="text-base-content/60">Import businesses from Google Places & other sources</p>
          </div>
        </div>

        <!-- Alert Message -->
        <%= if @message do %>
          <div class={["alert mb-6", message_class(@message)]}>
            <span>{elem(@message, 1)}</span>
            <button type="button" phx-click="dismiss_message" class="btn btn-sm btn-ghost">✕</button>
          </div>
        <% end %>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <!-- Scrape Control Panel -->
          <div class="card bg-base-200">
            <div class="card-body">
              <h2 class="card-title">
                <span class="hero-magnifying-glass-circle w-6 h-6"></span>
                Import Businesses
              </h2>

              <form phx-change="form_change" phx-submit="start_scrape">
                <!-- Source Selection -->
                <div class="form-control mt-4">
                  <label class="label">
                    <span class="label-text font-medium">Data Source</span>
                  </label>
                  <div class="flex gap-4">
                    <label class="label cursor-pointer gap-2">
                      <input
                        type="radio"
                        name="source"
                        value="google_places"
                        class="radio radio-primary"
                        checked={@scrape_source == "google_places"}
                      />
                      <span class="label-text">
                        Google Places
                        <span class="badge badge-success badge-xs ml-1">Recommended</span>
                      </span>
                    </label>
                    <label class="label cursor-pointer gap-2">
                      <input
                        type="radio"
                        name="source"
                        value="paginas_amarillas"
                        class="radio"
                        checked={@scrape_source == "paginas_amarillas"}
                      />
                      <span class="label-text">Páginas Amarillas</span>
                    </label>
                  </div>
                </div>

                <div class="form-control mt-4">
                  <label class="label">
                    <span class="label-text">City</span>
                  </label>
                  <select
                    class="select select-bordered"
                    name="city"
                  >
                    <option value="">Select a city...</option>
                    <%= for city <- @cities do %>
                      <option
                        value={city.id}
                        selected={@selected_city && @selected_city.id == city.id}
                      >
                        {city.name}
                      </option>
                    <% end %>
                  </select>
                </div>

                <div class="form-control mt-4">
                  <label class="label">
                    <span class="label-text">Category</span>
                  </label>
                  <select
                    class="select select-bordered"
                    name="category"
                  >
                    <option value="">Select a category...</option>
                    <%= for category <- @categories do %>
                      <option
                        value={category.id}
                        selected={@selected_category && @selected_category.id == category.id}
                      >
                        {category.name} ({category.name_es || Scraper.translate_category(category.slug)})
                      </option>
                    <% end %>
                  </select>
                </div>

                <%= if @selected_city && @selected_category do %>
                  <div class="alert alert-info mt-4">
                    <span class="hero-information-circle w-5 h-5"></span>
                    <span>
                      Will search for:
                      <strong>"{Scraper.translate_category(@selected_category.slug)} {@selected_city.name}"</strong>
                    </span>
                  </div>
                <% end %>

                <div class="card-actions mt-6 flex-wrap">
                  <button
                    type="submit"
                    class="btn btn-primary"
                    disabled={@scraping || is_nil(@selected_city) || is_nil(@selected_category)}
                  >
                    <%= if @scraping do %>
                      <span class="loading loading-spinner loading-sm"></span>
                    <% else %>
                      <span class="hero-play w-5 h-5"></span>
                    <% end %>
                    Start Import
                  </button>

                  <%= if @selected_city && @scrape_source == "google_places" do %>
                    <button
                      type="button"
                      phx-click="scrape_all_city"
                      class="btn btn-secondary btn-outline"
                      disabled={@scraping}
                    >
                      <span class="hero-squares-2x2 w-5 h-5"></span>
                      Import All Categories
                    </button>
                  <% end %>

                  <%= if @scraping do %>
                    <button type="button" phx-click="stop_all" class="btn btn-error btn-outline">
                      <span class="hero-stop w-5 h-5"></span>
                      Stop
                    </button>
                  <% end %>
                </div>
              </form>
            </div>
          </div>

          <!-- Status Panel -->
          <div class="card bg-base-200">
            <div class="card-body">
              <h2 class="card-title">
                <span class="hero-chart-bar w-6 h-6"></span>
                Status
                <%= if @scraping do %>
                  <span class="badge badge-success badge-sm animate-pulse">Active</span>
                <% else %>
                  <span class="badge badge-ghost badge-sm">Idle</span>
                <% end %>
              </h2>

              <!-- Oban Jobs -->
              <%= if length(@oban_jobs) > 0 do %>
                <div class="mt-4">
                  <h3 class="font-medium text-sm mb-2">Queued Jobs</h3>
                  <div class="space-y-2">
                    <%= for job <- @oban_jobs do %>
                      <div class="flex items-center gap-2 text-sm">
                        <span class={["badge badge-sm", if(job.state == "executing", do: "badge-info animate-pulse", else: "badge-warning")]}>
                          {job.state}
                        </span>
                        <span class="font-mono">{job.args["query"]}</span>
                      </div>
                    <% end %>
                  </div>
                </div>
              <% end %>

              <!-- Crawly Spiders -->
              <%= if map_size(@spider_status) > 0 do %>
                <div class="mt-4">
                  <h3 class="font-medium text-sm mb-2">Running Spiders</h3>
                  <%= for {spider, _status} <- @spider_status do %>
                    <div class="badge badge-info badge-sm">{inspect(spider)}</div>
                  <% end %>
                </div>
              <% end %>

              <%= if length(@oban_jobs) == 0 && map_size(@spider_status) == 0 do %>
                <div class="text-center py-6 text-base-content/50">
                  <span class="hero-clock w-10 h-10 mx-auto mb-2"></span>
                  <p class="text-sm">No active jobs</p>
                </div>
              <% end %>

              <div class="divider">Database Stats</div>

              <div class="stats stats-vertical shadow">
                <div class="stat">
                  <div class="stat-title">Total Businesses</div>
                  <div class="stat-value text-primary">{business_count()}</div>
                </div>
                <div class="stat">
                  <div class="stat-title">Pending Enrichment</div>
                  <div class="stat-value text-warning">{pending_count()}</div>
                </div>
                <div class="stat">
                  <div class="stat-title">English Speaking</div>
                  <div class="stat-value text-success">{english_count()}</div>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- Recent Jobs -->
        <div class="card bg-base-200 mt-6">
          <div class="card-body">
            <h2 class="card-title">
              <span class="hero-clock w-6 h-6"></span>
              Recent Import Jobs
            </h2>

            <%= if length(@recent_jobs) > 0 do %>
              <div class="overflow-x-auto">
                <table class="table table-sm">
                  <thead>
                    <tr>
                      <th>Source</th>
                      <th>Query</th>
                      <th>City</th>
                      <th>Category</th>
                      <th>Status</th>
                      <th>Found</th>
                      <th>Created</th>
                      <th>Time</th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for job <- @recent_jobs do %>
                      <tr>
                        <td>
                          <span class={["badge badge-sm", source_badge_class(job.source)]}>
                            {format_source(job.source)}
                          </span>
                        </td>
                        <td class="font-mono text-xs max-w-32 truncate">{job.query}</td>
                        <td>{job.city && job.city.name}</td>
                        <td>{job.category && job.category.name}</td>
                        <td>
                          <span class={["badge badge-sm", status_badge_class(job.status)]}>
                            {job.status}
                          </span>
                        </td>
                        <td class="text-center">{job.businesses_found || 0}</td>
                        <td class="text-center">{job.businesses_created || 0}</td>
                        <td class="text-xs text-base-content/60">
                          {format_time(job.started_at)}
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            <% else %>
              <div class="text-center py-8 text-base-content/50">
                <p>No import jobs yet. Start by selecting a city and category above.</p>
              </div>
            <% end %>
          </div>
        </div>

        <!-- Quick Actions -->
        <div class="card bg-base-200 mt-6">
          <div class="card-body">
            <h2 class="card-title">Quick Links</h2>
            <div class="flex flex-wrap gap-4 mt-4">
              <.link navigate={~p"/oban"} class="btn btn-outline btn-sm" target="_blank">
                <span class="hero-queue-list w-4 h-4"></span>
                Oban Dashboard
              </.link>
              <.link navigate={~p"/search"} class="btn btn-outline btn-sm">
                <span class="hero-magnifying-glass w-4 h-4"></span>
                Search Businesses
              </.link>
              <.link navigate={~p"/dev/dashboard"} class="btn btn-outline btn-sm" target="_blank">
                <span class="hero-chart-pie w-4 h-4"></span>
                Phoenix Dashboard
              </.link>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp message_class({:success, _}), do: "alert-success"
  defp message_class({:error, _}), do: "alert-error"
  defp message_class({:warning, _}), do: "alert-warning"
  defp message_class(_), do: "alert-info"

  defp status_badge_class(:pending), do: "badge-warning"
  defp status_badge_class(:running), do: "badge-info"
  defp status_badge_class(:completed), do: "badge-success"
  defp status_badge_class(:failed), do: "badge-error"
  defp status_badge_class(_), do: "badge-ghost"

  defp source_badge_class(:google_places), do: "badge-primary"
  defp source_badge_class(:paginas_amarillas), do: "badge-secondary"
  defp source_badge_class(_), do: "badge-ghost"

  defp format_source(:google_places), do: "Google"
  defp format_source(:paginas_amarillas), do: "P. Amarillas"
  defp format_source(other), do: to_string(other)

  defp business_count do
    Business.list!() |> length()
  end

  defp pending_count do
    Business.list!()
    |> Enum.count(& &1.status == :pending)
  end

  defp english_count do
    Business.list!()
    |> Enum.count(& &1.speaks_english == true)
  end

  defp format_time(nil), do: "-"
  defp format_time(dt) do
    Calendar.strftime(dt, "%m/%d %H:%M")
  end
end
