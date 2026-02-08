defmodule GaliciaLocalWeb.Admin.DiscoveryLive do
  @moduledoc """
  Admin dashboard for monitoring discovery crawls.
  Shows crawl status, page counts, and extraction results.
  """
  use GaliciaLocalWeb, :live_view

  alias GaliciaLocal.Directory.DiscoveryCrawl

  @refresh_interval :timer.seconds(5)

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Process.send_after(self(), :refresh, @refresh_interval)

    {:ok,
     socket
     |> assign(:page_title, "Discovery Crawls")
     |> assign(:city_names, load_city_names())
     |> load_crawls()}
  end

  @impl true
  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, @refresh_interval)
    {:noreply, load_crawls(socket)}
  end

  @impl true
  def handle_event("process_crawl", %{"crawl-id" => crawl_id}, socket) do
    %{crawl_id: crawl_id}
    |> GaliciaLocal.Workers.DiscoveryProcessWorker.new()
    |> Oban.insert()

    {:noreply, put_flash(socket, :info, "Processing queued for #{String.slice(crawl_id, 0, 8)}...")}
  end

  def handle_event("reprocess_crawl", %{"crawl-id" => crawl_id}, socket) do
    case DiscoveryCrawl.get_by_crawl_id(crawl_id) do
      {:ok, crawl} ->
        # Reset to crawled so it can be processed again
        pages = count_pages(crawl_id)
        DiscoveryCrawl.mark_crawled(crawl, pages)

        %{crawl_id: crawl_id}
        |> GaliciaLocal.Workers.DiscoveryProcessWorker.new()
        |> Oban.insert()

        {:noreply, put_flash(socket, :info, "Re-processing queued for #{String.slice(crawl_id, 0, 8)}...")}

      _ ->
        {:noreply, put_flash(socket, :error, "Crawl not found")}
    end
  end

  defp load_crawls(socket) do
    crawls = DiscoveryCrawl.list!() |> Ash.load!([:city, :region])
    assign(socket, :crawls, crawls)
  end

  defp load_city_names do
    %{rows: rows} = GaliciaLocal.Repo.query!("SELECT id::text, name FROM cities")
    Map.new(rows, fn [id, name] -> {id, name} end)
  end

  defp count_pages(crawl_id) do
    dir = Path.join(GaliciaLocal.Scraper.discovery_data_dir(), crawl_id)

    case File.ls(dir) do
      {:ok, files} -> Enum.count(files, &String.starts_with?(&1, "page_"))
      {:error, _} -> 0
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200">
      <header class="bg-base-100 border-b border-base-300 sticky top-0 z-50 shadow-sm">
        <div class="container mx-auto px-6 py-3">
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-4">
              <.link navigate={~p"/admin"} class="btn btn-ghost btn-sm btn-circle">
                <span class="hero-arrow-left w-5 h-5"></span>
              </.link>
              <div>
                <h1 class="text-2xl font-bold">{gettext("Discovery Crawls")}</h1>
                <p class="text-base-content/60 text-sm">{gettext("Monitor web crawls and business extraction")}</p>
              </div>
            </div>
            <div class="flex items-center gap-2">
              <span class="text-sm text-base-content/70">{length(@crawls)} {gettext("crawls")}</span>
              <.link navigate={~p"/admin/regions"} class="btn btn-ghost btn-sm">
                <span class="hero-plus w-4 h-4"></span>
                {gettext("New Crawl")}
              </.link>
            </div>
          </div>
        </div>
      </header>

      <main class="container mx-auto max-w-6xl px-4 py-8">
        <%= if @crawls == [] do %>
          <div class="card bg-base-100 shadow-md">
            <div class="card-body text-center py-12">
              <span class="hero-globe-alt w-12 h-12 text-base-content/20 mx-auto"></span>
              <p class="text-base-content/60 mt-4">{gettext("No discovery crawls yet")}</p>
              <p class="text-sm text-base-content/40">{gettext("Start a crawl from the Regions page")}</p>
            </div>
          </div>
        <% else %>
          <.stats_bar crawls={@crawls} />

          <div class="overflow-x-auto mt-6">
            <table class="table table-sm bg-base-100 shadow-md rounded-lg">
              <thead>
                <tr>
                  <th>{gettext("Crawl")}</th>
                  <th>{gettext("City")}</th>
                  <th>{gettext("Status")}</th>
                  <th class="text-right">{gettext("Pages")}</th>
                  <th class="text-right">{gettext("Businesses")}</th>
                  <th>{gettext("Started")}</th>
                  <th>{gettext("Duration")}</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                <%= for crawl <- @crawls do %>
                  <tr>
                    <td>
                      <span class="font-mono text-xs">{String.slice(crawl.crawl_id, 0, 10)}</span>
                    </td>
                    <td>
                      <%= if crawl.city do %>
                        <span class="font-medium">{crawl.city.name}</span>
                      <% else %>
                        <span class="text-base-content/40">-</span>
                      <% end %>
                    </td>
                    <td>
                      <.status_badge status={crawl.status} />
                    </td>
                    <td class="text-right">
                      <span class="font-mono text-sm">
                        {crawl.pages_crawled}
                        <span class="text-base-content/40">/ {crawl.max_pages}</span>
                      </span>
                    </td>
                    <td class="text-right">
                      <%= if crawl.status in [:completed, :processing] do %>
                        <span class="text-success font-mono text-sm">{crawl.businesses_created}</span>
                        <%= if crawl.businesses_skipped > 0 do %>
                          <span class="text-base-content/40 text-xs ml-1">+{crawl.businesses_skipped} skip</span>
                        <% end %>
                        <%= if crawl.businesses_failed > 0 do %>
                          <span class="text-error text-xs ml-1">+{crawl.businesses_failed} fail</span>
                        <% end %>
                      <% else %>
                        <span class="text-base-content/40">-</span>
                      <% end %>
                    </td>
                    <td>
                      <span class="text-xs">{format_time(crawl.started_at)}</span>
                    </td>
                    <td>
                      <span class="text-xs text-base-content/60">{format_duration(crawl)}</span>
                    </td>
                    <td>
                      <%= if crawl.status == :crawled do %>
                        <button
                          type="button"
                          phx-click="process_crawl"
                          phx-value-crawl-id={crawl.crawl_id}
                          class="btn btn-primary btn-xs"
                        >
                          Process Now
                        </button>
                      <% end %>
                      <%= if crawl.status in [:completed, :failed] do %>
                        <button
                          type="button"
                          phx-click="reprocess_crawl"
                          phx-value-crawl-id={crawl.crawl_id}
                          class="btn btn-ghost btn-xs"
                        >
                          Re-process
                        </button>
                      <% end %>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        <% end %>
      </main>
    </div>
    """
  end

  defp stats_bar(assigns) do
    active = Enum.count(assigns.crawls, &(&1.status in [:crawling, :processing]))
    completed = Enum.count(assigns.crawls, &(&1.status == :completed))
    total_businesses = assigns.crawls |> Enum.map(& &1.businesses_created) |> Enum.sum()
    total_pages = assigns.crawls |> Enum.map(& &1.pages_crawled) |> Enum.sum()

    assigns =
      assigns
      |> assign(:active, active)
      |> assign(:completed, completed)
      |> assign(:total_businesses, total_businesses)
      |> assign(:total_pages, total_pages)

    ~H"""
    <div class="stats shadow bg-base-100 w-full">
      <div class="stat">
        <div class="stat-title">{gettext("Total Crawls")}</div>
        <div class="stat-value text-2xl">{length(@crawls)}</div>
      </div>
      <div class="stat">
        <div class="stat-title">{gettext("Active")}</div>
        <div class="stat-value text-2xl text-info">{@active}</div>
      </div>
      <div class="stat">
        <div class="stat-title">{gettext("Completed")}</div>
        <div class="stat-value text-2xl text-success">{@completed}</div>
      </div>
      <div class="stat">
        <div class="stat-title">{gettext("Pages Crawled")}</div>
        <div class="stat-value text-2xl">{@total_pages}</div>
      </div>
      <div class="stat">
        <div class="stat-title">{gettext("Businesses Found")}</div>
        <div class="stat-value text-2xl text-primary">{@total_businesses}</div>
      </div>
    </div>
    """
  end

  defp status_badge(%{status: :crawling} = assigns) do
    ~H"""
    <span class="badge badge-info badge-sm gap-1">
      <span class="loading loading-spinner loading-xs"></span>
      Crawling
    </span>
    """
  end

  defp status_badge(%{status: :crawled} = assigns) do
    ~H"""
    <span class="badge badge-warning badge-sm">Crawled</span>
    """
  end

  defp status_badge(%{status: :processing} = assigns) do
    ~H"""
    <span class="badge badge-info badge-sm gap-1">
      <span class="loading loading-spinner loading-xs"></span>
      Processing
    </span>
    """
  end

  defp status_badge(%{status: :completed} = assigns) do
    ~H"""
    <span class="badge badge-success badge-sm">Completed</span>
    """
  end

  defp status_badge(%{status: :failed} = assigns) do
    ~H"""
    <span class="badge badge-error badge-sm">Failed</span>
    """
  end

  defp status_badge(assigns) do
    ~H"""
    <span class="badge badge-ghost badge-sm">{@status}</span>
    """
  end

  defp format_time(nil), do: "-"

  defp format_time(dt) do
    Calendar.strftime(dt, "%b %d %H:%M")
  end

  defp format_duration(%{started_at: nil}), do: "-"

  defp format_duration(%{status: status, completed_at: completed_at, started_at: started_at})
       when status in [:completed, :failed] and not is_nil(completed_at) do
    diff = DateTime.diff(completed_at, started_at, :second)
    format_seconds(diff)
  end

  defp format_duration(%{status: status, started_at: started_at})
       when status in [:crawling, :processing, :crawled] do
    diff = DateTime.diff(DateTime.utc_now(), started_at, :second)
    format_seconds(diff) <> "..."
  end

  defp format_duration(_), do: "-"

  defp format_seconds(seconds) when seconds < 60, do: "#{seconds}s"
  defp format_seconds(seconds) when seconds < 3600, do: "#{div(seconds, 60)}m #{rem(seconds, 60)}s"
  defp format_seconds(seconds), do: "#{div(seconds, 3600)}h #{div(rem(seconds, 3600), 60)}m"
end
