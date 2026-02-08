defmodule GaliciaLocalWeb.Admin.PipelineLive do
  @moduledoc """
  Admin page for monitoring the content pipeline.
  Shows funnel visualization, throughput, translation coverage, and queue depths.
  """
  use GaliciaLocalWeb, :live_view

  alias GaliciaLocal.Pipeline.PipelineStatus
  alias GaliciaLocal.Directory.Region

  @refresh_interval :timer.seconds(10)

  @impl true
  def mount(_params, _session, socket) do
    regions = Region.list_active!()
    current_region = socket.assigns[:current_region]
    region_id = current_region && current_region.id

    if connected?(socket), do: Process.send_after(self(), :refresh, @refresh_interval)

    {:ok,
     socket
     |> assign(:page_title, "Content Pipeline")
     |> assign(:regions, regions)
     |> assign(:selected_region_id, region_id)
     |> load_status(region_id)}
  end

  @impl true
  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, @refresh_interval)
    {:noreply, load_status(socket, socket.assigns.selected_region_id)}
  end

  @impl true
  def handle_event("select_region", %{"region_id" => "all"}, socket) do
    {:noreply, socket |> assign(:selected_region_id, nil) |> load_status(nil)}
  end

  def handle_event("select_region", %{"region_id" => id}, socket) do
    {:noreply, socket |> assign(:selected_region_id, id) |> load_status(id)}
  end

  defp load_status(socket, region_id) do
    status = PipelineStatus.summary(region_id)

    socket
    |> assign(:funnel, status.funnel)
    |> assign(:throughput, status.throughput)
    |> assign(:translation_coverage, status.translation_coverage)
    |> assign(:queue_depths, status.queue_depths)
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
                <h1 class="text-3xl font-bold">{gettext("Content Pipeline")}</h1>
                <p class="text-base-content/60 mt-1">{gettext("Monitor enrichment, translation, and discovery progress")}</p>
              </div>
            </div>

            <div class="flex items-center gap-3">
              <form phx-change="select_region">
                <select
                  name="region_id"
                  class="select select-bordered select-sm"
                >
                  <option value="all" selected={is_nil(@selected_region_id)}>{gettext("All Regions")}</option>
                  <%= for region <- @regions do %>
                    <option value={region.id} selected={region.id == @selected_region_id}>{region.name}</option>
                  <% end %>
                </select>
              </form>
              <span class="badge badge-ghost badge-sm">{gettext("Auto-refresh 10s")}</span>
            </div>
          </div>
        </div>
      </header>

      <main class="container mx-auto max-w-6xl px-4 py-8">
        <%!-- Throughput Stats --%>
        <div class="stats stats-vertical lg:stats-horizontal shadow w-full mb-8">
          <div class="stat">
            <div class="stat-figure text-primary">
              <span class="hero-sparkles w-8 h-8"></span>
            </div>
            <div class="stat-title">{gettext("Enriched (24h)")}</div>
            <div class="stat-value text-primary">{@throughput.enriched_24h}</div>
            <div class="stat-desc">{gettext("%{count} in 7 days", count: @throughput.enriched_7d)}</div>
          </div>
          <div class="stat">
            <div class="stat-figure text-secondary">
              <span class="hero-language w-8 h-8"></span>
            </div>
            <div class="stat-title">{gettext("Translated (24h)")}</div>
            <div class="stat-value text-secondary">{@throughput.translated_24h}</div>
            <div class="stat-desc">{gettext("unique businesses")}</div>
          </div>
          <div class="stat">
            <div class="stat-figure text-accent">
              <span class="hero-building-storefront w-8 h-8"></span>
            </div>
            <div class="stat-title">{gettext("Total Businesses")}</div>
            <div class="stat-value text-accent">{@funnel.total}</div>
            <div class="stat-desc">{gettext("across all statuses")}</div>
          </div>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-8">
          <%!-- Pipeline Funnel --%>
          <div class="card bg-base-100 shadow-xl">
            <div class="card-body">
              <h2 class="card-title">
                <span class="hero-funnel w-5 h-5 text-primary"></span>
                {gettext("Pipeline Funnel")}
              </h2>

              <div class="space-y-3 mt-4">
                <.funnel_row label="Pending" count={@funnel.pending} total={@funnel.total} color="warning" />
                <.funnel_row label="Researching" count={@funnel.researching} total={@funnel.total} color="info" />
                <.funnel_row label="Researched" count={@funnel.researched} total={@funnel.total} color="info" />
                <.funnel_row label="Enriched" count={@funnel.enriched} total={@funnel.total} color="success" />
                <.funnel_row label="Verified" count={@funnel.verified} total={@funnel.total} color="primary" />
                <%= if @funnel.failed > 0 do %>
                  <.funnel_row label="Failed" count={@funnel.failed} total={@funnel.total} color="error" />
                <% end %>
              </div>
            </div>
          </div>

          <%!-- Translation Coverage --%>
          <div class="card bg-base-100 shadow-xl">
            <div class="card-body">
              <h2 class="card-title">
                <span class="hero-language w-5 h-5 text-secondary"></span>
                {gettext("Translation Coverage")}
              </h2>

              <div class="space-y-4 mt-4">
                <%= if map_size(@translation_coverage) == 0 do %>
                  <p class="text-base-content/50">{gettext("No target locales configured")}</p>
                <% end %>
                <%= for {locale, %{translated: translated, total: total}} <- @translation_coverage do %>
                  <% pct = if total > 0, do: round(translated / total * 100), else: 0 %>
                  <div class="flex items-center gap-4">
                    <div class="w-12">
                      <span class="font-mono font-medium text-sm">{String.upcase(locale)}</span>
                    </div>
                    <div class="flex-1">
                      <progress class={"progress #{progress_color(pct)} w-full"} value={translated} max={max(total, 1)} />
                    </div>
                    <div class="w-28 text-right">
                      <span class="text-sm font-mono">{translated}/{total}</span>
                      <span class={"text-xs ml-1 #{if pct == 100, do: "text-success", else: "text-base-content/50"}"}>
                        ({pct}%)
                      </span>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        </div>

        <%!-- Queue Depths --%>
        <div class="card bg-base-100 shadow-xl">
          <div class="card-body">
            <h2 class="card-title">
              <span class="hero-queue-list w-5 h-5 text-accent"></span>
              {gettext("Oban Queue Depths")}
            </h2>

            <%= if map_size(@queue_depths) == 0 do %>
              <p class="text-base-content/50 mt-4">{gettext("All queues are empty")}</p>
            <% else %>
              <div class="overflow-x-auto mt-4">
                <table class="table table-sm">
                  <thead>
                    <tr>
                      <th>{gettext("Queue")}</th>
                      <th class="text-right">{gettext("Available")}</th>
                      <th class="text-right">{gettext("Executing")}</th>
                      <th class="text-right">{gettext("Scheduled")}</th>
                      <th class="text-right">{gettext("Retryable")}</th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for {queue, depths} <- Enum.sort(@queue_depths) do %>
                      <tr>
                        <td class="font-medium font-mono text-sm">{queue}</td>
                        <td class="text-right font-mono">
                          <span class={if depths.available > 0, do: "badge badge-warning badge-sm", else: "text-base-content/40"}>
                            {depths.available}
                          </span>
                        </td>
                        <td class="text-right font-mono">
                          <span class={if depths.executing > 0, do: "badge badge-info badge-sm", else: "text-base-content/40"}>
                            {depths.executing}
                          </span>
                        </td>
                        <td class="text-right font-mono">
                          <span class={if depths.scheduled > 0, do: "badge badge-ghost badge-sm", else: "text-base-content/40"}>
                            {depths.scheduled}
                          </span>
                        </td>
                        <td class="text-right font-mono">
                          <span class={if depths.retryable > 0, do: "badge badge-error badge-sm", else: "text-base-content/40"}>
                            {depths.retryable}
                          </span>
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            <% end %>
          </div>
        </div>
      </main>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :count, :integer, required: true
  attr :total, :integer, required: true
  attr :color, :string, default: "primary"
  defp funnel_row(assigns) do
    assigns = assign(assigns, :pct, if(assigns.total > 0, do: round(assigns.count / assigns.total * 100), else: 0))

    ~H"""
    <div class="flex items-center gap-4">
      <div class="w-28">
        <span class="text-sm font-medium">{@label}</span>
      </div>
      <div class="flex-1">
        <progress class={"progress progress-#{@color} w-full"} value={@count} max={max(@total, 1)} />
      </div>
      <div class="w-24 text-right">
        <span class="font-mono font-bold">{@count}</span>
        <span class="text-xs text-base-content/50 ml-1">({@pct}%)</span>
      </div>
    </div>
    """
  end

  defp progress_color(pct) when pct >= 90, do: "progress-success"
  defp progress_color(pct) when pct >= 50, do: "progress-warning"
  defp progress_color(_pct), do: "progress-error"
end
