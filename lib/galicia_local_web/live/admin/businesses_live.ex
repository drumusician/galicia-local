defmodule GaliciaLocalWeb.Admin.BusinessesLive do
  @moduledoc """
  Admin interface for managing business listings.
  """
  use GaliciaLocalWeb, :live_view

  alias GaliciaLocal.Directory.Business
  alias GaliciaLocalWeb.Layouts

  @impl true
  def mount(_params, _session, socket) do
    businesses = Business.list!()
                 |> Ash.load!([:city, :category])
                 |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})

    {:ok,
     socket
     |> assign(:page_title, "Manage Businesses")
     |> assign(:businesses, businesses)
     |> assign(:filter, "all")}
  end

  @impl true
  def handle_event("filter", %{"status" => status}, socket) do
    {:noreply, assign(socket, :filter, status)}
  end

  @impl true
  def handle_event("enrich", %{"id" => id}, socket) do
    case Business.get_by_id(id) do
      {:ok, business} ->
        case Business.enrich_with_llm(business) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, "#{business.name} enriched successfully")
             |> reload_businesses()}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to start enrichment")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Business not found")}
    end
  end

  defp reload_businesses(socket) do
    businesses = Business.list!()
                 |> Ash.load!([:city, :category])
                 |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})

    assign(socket, :businesses, businesses)
  end

  defp filtered_businesses(businesses, "all"), do: businesses
  defp filtered_businesses(businesses, status) do
    status_atom = String.to_existing_atom(status)
    Enum.filter(businesses, &(&1.status == status_atom))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.flash_group flash={@flash} />
    <div class="min-h-screen bg-base-200">
      <header class="bg-base-100 border-b border-base-300 sticky top-0 z-50">
        <div class="container mx-auto px-6 py-4">
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-4">
              <.link navigate={~p"/admin"} class="btn btn-ghost btn-sm">
                <span class="hero-arrow-left w-4 h-4"></span>
              </.link>
              <h1 class="text-2xl font-bold">Manage Businesses</h1>
            </div>
            <div class="flex items-center gap-2">
              <span class="text-sm text-base-content/70">{length(@businesses)} total</span>
            </div>
          </div>
        </div>
      </header>

      <main class="container mx-auto px-6 py-8">
        <!-- Filters -->
        <div class="flex gap-2 mb-6">
          <button
            type="button"
            phx-click="filter"
            phx-value-status="all"
            class={["btn btn-sm", if(@filter == "all", do: "btn-primary", else: "btn-ghost")]}
          >
            All ({length(@businesses)})
          </button>
          <button
            type="button"
            phx-click="filter"
            phx-value-status="pending"
            class={["btn btn-sm", if(@filter == "pending", do: "btn-warning", else: "btn-ghost")]}
          >
            Pending ({Enum.count(@businesses, &(&1.status == :pending))})
          </button>
          <button
            type="button"
            phx-click="filter"
            phx-value-status="enriched"
            class={["btn btn-sm", if(@filter == "enriched", do: "btn-success", else: "btn-ghost")]}
          >
            Enriched ({Enum.count(@businesses, &(&1.status == :enriched))})
          </button>
        </div>

        <!-- Business Table -->
        <div class="card bg-base-100 shadow-xl">
          <div class="card-body p-0">
            <div class="overflow-x-auto">
              <table class="table table-sm">
                <thead>
                  <tr>
                    <th>Name</th>
                    <th>City</th>
                    <th>Category</th>
                    <th>Status</th>
                    <th>Rating</th>
                    <th>English</th>
                    <th>Added</th>
                    <th></th>
                  </tr>
                </thead>
                <tbody>
                  <%= for business <- filtered_businesses(@businesses, @filter) do %>
                    <tr>
                      <td class="font-medium max-w-48 truncate">{business.name}</td>
                      <td>{business.city && business.city.name}</td>
                      <td>{business.category && business.category.name}</td>
                      <td>
                        <span class={["badge badge-sm", status_class(business.status)]}>
                          {business.status}
                        </span>
                      </td>
                      <td>
                        <%= if business.rating do %>
                          <span class="text-warning">★</span> {Decimal.round(business.rating, 1)}
                        <% else %>
                          -
                        <% end %>
                      </td>
                      <td>
                        <%= if business.speaks_english do %>
                          <span class="badge badge-success badge-xs">Yes</span>
                        <% else %>
                          <span class="badge badge-ghost badge-xs">No</span>
                        <% end %>
                      </td>
                      <td class="text-xs text-base-content/60">
                        {Calendar.strftime(business.inserted_at, "%b %d")}
                      </td>
                      <td>
                        <div class="flex gap-1">
                          <.link navigate={~p"/businesses/#{business.id}"} class="btn btn-ghost btn-xs">
                            View
                          </.link>
                          <%= if business.status == :pending do %>
                            <button
                              type="button"
                              phx-click="enrich"
                              phx-value-id={business.id}
                              phx-disable-with="Enriching..."
                              class="btn btn-primary btn-xs"
                            >
                              Enrich
                            </button>
                          <% end %>
                        </div>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          </div>
        </div>
      </main>
    </div>
    """
  end

  defp status_class(:pending), do: "badge-warning"
  defp status_class(:enriched), do: "badge-success"
  defp status_class(:verified), do: "badge-info"
  defp status_class(:failed), do: "badge-error"
  defp status_class(_), do: "badge-ghost"
end
