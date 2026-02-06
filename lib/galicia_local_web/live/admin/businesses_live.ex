defmodule GaliciaLocalWeb.Admin.BusinessesLive do
  @moduledoc """
  Admin interface for managing business listings.
  Supports pagination, filtering, search, and CRUD operations.
  """
  use GaliciaLocalWeb, :live_view

  alias GaliciaLocal.Directory.{Business, City, Category}

  require Ash.Query

  @per_page 25

  @impl true
  def mount(_params, _session, socket) do
    region = socket.assigns[:current_region]
    tenant_opts = if region, do: [tenant: region.id], else: []
    region_slug = if region, do: region.slug, else: "galicia"

    # Filter cities by current region
    cities =
      City
      |> then(fn q -> if region, do: Ash.Query.set_tenant(q, region.id), else: q end)
      |> Ash.read!()
      |> Enum.sort_by(& &1.name)

    categories = Category.list!() |> Enum.sort_by(& &1.name)

    {:ok,
     socket
     |> assign(:page_title, "Manage Businesses")
     |> assign(:tenant_opts, tenant_opts)
     |> assign(:region_slug, region_slug)
     |> assign(:cities, cities)
     |> assign(:categories, categories)
     |> assign(:filter_status, "all")
     |> assign(:filter_city, nil)
     |> assign(:filter_category, nil)
     |> assign(:search_query, "")
     |> assign(:current_page, 1)
     |> assign(:creating, false)
     |> assign(:editing, nil)
     |> load_page()}
  end

  defp load_page(socket) do
    offset = (socket.assigns.current_page - 1) * @per_page
    region = socket.assigns[:current_region]

    page =
      Business
      |> Ash.Query.sort(inserted_at: :desc)
      |> maybe_filter_status(socket.assigns.filter_status)
      |> maybe_filter_city(socket.assigns.filter_city)
      |> maybe_filter_category(socket.assigns.filter_category)
      |> maybe_search(socket.assigns.search_query)
      |> Ash.Query.load([:city, :category])
      |> then(fn q -> if region, do: Ash.Query.set_tenant(q, region.id), else: q end)
      |> Ash.read!(page: [limit: @per_page, offset: offset, count: true])

    assign(socket, :page, page)
  end

  defp maybe_filter_status(query, "all"), do: query
  defp maybe_filter_status(query, "pending"), do: Ash.Query.filter(query, status == :pending)
  defp maybe_filter_status(query, "researching"), do: Ash.Query.filter(query, status == :researching)
  defp maybe_filter_status(query, "researched"), do: Ash.Query.filter(query, status == :researched)
  defp maybe_filter_status(query, "enriched"), do: Ash.Query.filter(query, status == :enriched)
  defp maybe_filter_status(query, "verified"), do: Ash.Query.filter(query, status == :verified)
  defp maybe_filter_status(query, "rejected"), do: Ash.Query.filter(query, status == :rejected)
  defp maybe_filter_status(query, "low_fit"), do: Ash.Query.filter(query, not is_nil(category_fit_score) and category_fit_score < 0.5)
  defp maybe_filter_status(query, _), do: query

  defp maybe_filter_city(query, nil), do: query
  defp maybe_filter_city(query, ""), do: query

  defp maybe_filter_city(query, city_id) do
    Ash.Query.filter(query, city_id == ^city_id)
  end

  defp maybe_filter_category(query, nil), do: query
  defp maybe_filter_category(query, ""), do: query

  defp maybe_filter_category(query, category_id) do
    Ash.Query.filter(query, category_id == ^category_id)
  end

  defp maybe_search(query, ""), do: query
  defp maybe_search(query, nil), do: query

  defp maybe_search(query, search) do
    Ash.Query.filter(query, contains(name, ^search))
  end

  # Events

  @impl true
  def handle_event("search", %{"search" => query}, socket) do
    {:noreply,
     socket
     |> assign(:search_query, query)
     |> assign(:current_page, 1)
     |> load_page()}
  end

  @impl true
  def handle_event("filter", %{"status" => status}, socket) do
    {:noreply,
     socket
     |> assign(:filter_status, status)
     |> assign(:current_page, 1)
     |> load_page()}
  end

  @impl true
  def handle_event("filter_city", %{"city" => city_id}, socket) do
    {:noreply,
     socket
     |> assign(:filter_city, city_id)
     |> assign(:current_page, 1)
     |> load_page()}
  end

  @impl true
  def handle_event("filter_category", %{"category" => category_id}, socket) do
    {:noreply,
     socket
     |> assign(:filter_category, category_id)
     |> assign(:current_page, 1)
     |> load_page()}
  end

  @impl true
  def handle_event("page", %{"page" => page}, socket) do
    {:noreply,
     socket
     |> assign(:current_page, String.to_integer(page))
     |> load_page()}
  end

  @impl true
  def handle_event("new", _params, socket) do
    {:noreply, assign(socket, :creating, true)}
  end

  @impl true
  def handle_event("edit", %{"id" => id}, socket) do
    case Business.get_by_id(id) do
      {:ok, business} ->
        business = Ash.load!(business, [:city, :category])
        {:noreply, assign(socket, :editing, business)}

      _ ->
        {:noreply, put_flash(socket, :error, "Business not found")}
    end
  end

  @impl true
  def handle_event("cancel", _params, socket) do
    {:noreply, socket |> assign(:creating, false) |> assign(:editing, nil)}
  end

  @impl true
  def handle_event("create_business", %{"business" => params}, socket) do
    region = socket.assigns[:current_region]
    params = Map.put(params, "status", "pending")

    # Set region_id from current region
    params =
      if region do
        Map.put(params, "region_id", region.id)
      else
        params
      end

    params =
      if params["slug"] in [nil, ""] do
        Map.put(params, "slug", Slug.slugify(params["name"] || ""))
      else
        params
      end

    case Business.create(params) do
      {:ok, business} ->
        {:noreply,
         socket
         |> assign(:creating, false)
         |> put_flash(:info, "#{business.name} created successfully")
         |> load_page()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to create business")}
    end
  end

  @impl true
  def handle_event("save_business", %{"business" => params}, socket) do
    business = socket.assigns.editing

    case Ash.update(business, params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:editing, nil)
         |> put_flash(:info, "Business updated successfully")
         |> load_page()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update business")}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    case Business.get_by_id(id) do
      {:ok, business} ->
        case Ash.destroy(business) do
          :ok ->
            {:noreply,
             socket
             |> put_flash(:info, "#{business.name} deleted")
             |> load_page()}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to delete business")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Business not found")}
    end
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
             |> load_page()}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to enrich business")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Business not found")}
    end
  end

  @impl true
  def handle_event("move_to_suggested", %{"id" => id}, socket) do
    with {:ok, business} <- Business.get_by_id(id),
         slug when not is_nil(slug) <- business.suggested_category_slug,
         {:ok, category} <- Category.get_by_slug(slug) do
      case Ash.update(business, %{category_id: category.id, suggested_category_slug: nil, category_fit_score: nil}) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, "#{business.name} moved to #{category.name}")
           |> load_page()}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to move business")}
      end
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Could not find suggested category")}
    end
  end

  @impl true
  def handle_event("move_to_category", %{"business_id" => id, "category_id" => category_id}, socket) do
    if category_id == "" do
      {:noreply, socket}
    else
      with {:ok, business} <- Business.get_by_id(id),
           {:ok, category} <- Category.get_by_id(category_id) do
        case Ash.update(business, %{category_id: category.id, suggested_category_slug: nil, category_fit_score: nil}) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, "#{business.name} moved to #{category.name}")
             |> load_page()}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to move business")}
        end
      else
        _ ->
          {:noreply, put_flash(socket, :error, "Could not find business or category")}
      end
    end
  end

  @impl true
  def handle_event("reject", %{"id" => id}, socket) do
    with {:ok, business} <- Business.get_by_id(id) do
      case Ash.update(business, %{status: :rejected, category_fit_score: nil, suggested_category_slug: nil}) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, "#{business.name} rejected")
           |> load_page()}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to reject business")}
      end
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Business not found")}
    end
  end

  @impl true
  def handle_event("bulk_move_to_suggested", _params, socket) do
    region = socket.assigns[:current_region]

    businesses =
      Business
      |> Ash.Query.filter(not is_nil(category_fit_score) and category_fit_score < 0.5 and not is_nil(suggested_category_slug))
      |> maybe_filter_city(socket.assigns.filter_city)
      |> maybe_filter_category(socket.assigns.filter_category)
      |> then(fn q -> if region, do: Ash.Query.set_tenant(q, region.id), else: q end)
      |> Ash.read!()

    {moved, failed} =
      Enum.reduce(businesses, {0, 0}, fn business, {ok, err} ->
        case Category.get_by_slug(business.suggested_category_slug) do
          {:ok, category} ->
            case Ash.update(business, %{category_id: category.id, suggested_category_slug: nil, category_fit_score: nil}) do
              {:ok, _} -> {ok + 1, err}
              _ -> {ok, err + 1}
            end

          _ ->
            {ok, err + 1}
        end
      end)

    msg =
      case {moved, failed} do
        {m, 0} -> "Moved #{m} businesses to suggested categories"
        {m, f} -> "Moved #{m} businesses, #{f} failed (category not found)"
      end

    {:noreply,
     socket
     |> put_flash(:info, msg)
     |> load_page()}
  end

  @impl true
  def handle_event("bulk_reject", _params, socket) do
    region = socket.assigns[:current_region]

    businesses =
      Business
      |> Ash.Query.filter(not is_nil(category_fit_score) and category_fit_score < 0.5)
      |> maybe_filter_city(socket.assigns.filter_city)
      |> maybe_filter_category(socket.assigns.filter_category)
      |> then(fn q -> if region, do: Ash.Query.set_tenant(q, region.id), else: q end)
      |> Ash.read!()

    count =
      Enum.reduce(businesses, 0, fn business, acc ->
        case Ash.update(business, %{status: :rejected, category_fit_score: nil, suggested_category_slug: nil}) do
          {:ok, _} -> acc + 1
          _ -> acc
        end
      end)

    {:noreply,
     socket
     |> put_flash(:info, "Rejected #{count} businesses")
     |> load_page()}
  end

  @impl true
  def handle_event("bulk_re_enrich", _params, socket) do
    region = socket.assigns[:current_region]

    businesses =
      Business
      |> Ash.Query.filter(status in [:enriched, :verified])
      |> maybe_filter_category(socket.assigns.filter_category)
      |> maybe_filter_city(socket.assigns.filter_city)
      |> then(fn q -> if region, do: Ash.Query.set_tenant(q, region.id), else: q end)
      |> Ash.read!()

    count =
      Enum.reduce(businesses, 0, fn business, acc ->
        case Business.queue_re_enrichment(business) do
          {:ok, _} -> acc + 1
          _ -> acc
        end
      end)

    {:noreply,
     socket
     |> put_flash(:info, "Queued #{count} businesses for re-enrichment")
     |> load_page()}
  end

  # Helpers

  defp total_pages(page) do
    case page.count do
      nil -> 1
      0 -> 1
      count -> ceil(count / @per_page)
    end
  end

  defp page_range(current, total) do
    cond do
      total <= 7 -> 1..total
      current <= 4 -> 1..min(7, total)
      current >= total - 3 -> max(1, total - 6)..total
      true -> (current - 3)..(current + 3)
    end
    |> Enum.to_list()
  end

  defp showing_range(page, current_page) do
    start = (current_page - 1) * @per_page + 1
    finish = start + length(page.results) - 1
    {start, finish}
  end

  @impl true
  def render(assigns) do
    ~H"""
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
            <button type="button" phx-click="new" class="btn btn-primary btn-sm">
              <span class="hero-plus w-4 h-4"></span>
              Add Business
            </button>
          </div>
        </div>
      </header>

      <main class="container mx-auto px-6 py-8">
        <!-- Search -->
        <div class="mb-4">
          <form phx-change="search" phx-submit="search">
            <input
              type="text"
              name="search"
              value={@search_query}
              placeholder="Search businesses by name..."
              class="input input-bordered w-full max-w-md"
              phx-debounce="300"
            />
          </form>
        </div>

        <!-- Filters -->
        <div class="flex flex-wrap items-center gap-4 mb-6">
          <div class="flex gap-1">
            <button
              type="button" phx-click="filter" phx-value-status="all"
              class={["btn btn-sm", if(@filter_status == "all", do: "btn-primary", else: "btn-ghost")]}
            >
              All
            </button>
            <button
              type="button" phx-click="filter" phx-value-status="pending"
              class={["btn btn-sm", if(@filter_status == "pending", do: "btn-warning", else: "btn-ghost")]}
            >
              Pending
            </button>
            <button
              type="button" phx-click="filter" phx-value-status="enriched"
              class={["btn btn-sm", if(@filter_status == "enriched", do: "btn-success", else: "btn-ghost")]}
            >
              Enriched
            </button>
            <button
              type="button" phx-click="filter" phx-value-status="verified"
              class={["btn btn-sm", if(@filter_status == "verified", do: "btn-info", else: "btn-ghost")]}
            >
              Verified
            </button>
            <button
              type="button" phx-click="filter" phx-value-status="rejected"
              class={["btn btn-sm", if(@filter_status == "rejected", do: "btn-error", else: "btn-ghost")]}
            >
              Rejected
            </button>
            <button
              type="button" phx-click="filter" phx-value-status="low_fit"
              class={["btn btn-sm", if(@filter_status == "low_fit", do: "btn-accent", else: "btn-ghost")]}
            >
              Low fit
            </button>
          </div>

          <form phx-change="filter_city">
            <select name="city" class="select select-bordered select-sm">
              <option value="">All cities</option>
              <%= for city <- @cities do %>
                <option value={city.id} selected={@filter_city == city.id}>{city.name}</option>
              <% end %>
            </select>
          </form>

          <form phx-change="filter_category">
            <select name="category" class="select select-bordered select-sm">
              <option value="">All categories</option>
              <%= for cat <- @categories do %>
                <option value={cat.id} selected={@filter_category == cat.id}>{cat.name}</option>
              <% end %>
            </select>
          </form>

          <div class="flex items-center gap-2 ml-auto">
            <%= if @page.count do %>
              <span class="text-sm text-base-content/60">{@page.count} results</span>
            <% end %>
            <button
              type="button"
              phx-click="bulk_re_enrich"
              data-confirm="This will queue all enriched/verified businesses matching the current filters for re-enrichment. Continue?"
              class="btn btn-outline btn-warning btn-xs"
            >
              <span class="hero-arrow-path w-3 h-3"></span>
              Re-enrich filtered
            </button>
            <%= if @filter_status == "low_fit" do %>
              <button
                type="button"
                phx-click="bulk_move_to_suggested"
                data-confirm="Move all displayed businesses to their suggested categories?"
                class="btn btn-outline btn-accent btn-xs"
              >
                Move all to suggested
              </button>
              <button
                type="button"
                phx-click="bulk_reject"
                data-confirm="Reject ALL low-fit businesses matching the current filters? This cannot be undone."
                class="btn btn-outline btn-error btn-xs"
              >
                Reject all filtered
              </button>
            <% end %>
          </div>
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
                    <th>Fit</th>
                    <th>Added</th>
                    <th></th>
                  </tr>
                </thead>
                <tbody>
                  <%= for business <- @page.results do %>
                    <tr>
                      <td class="font-medium max-w-48 truncate">{business.name}</td>
                      <td class="text-sm">{business.city && business.city.name}</td>
                      <td class="text-sm">{business.category && business.category.name}</td>
                      <td>
                        <span class={["badge badge-sm", status_class(business.status)]}>
                          {business.status}
                        </span>
                      </td>
                      <td>
                        <%= if business.rating do %>
                          <span class="text-warning">★</span> {Decimal.round(business.rating, 1)}
                        <% else %>
                          <span class="text-base-content/30">-</span>
                        <% end %>
                      </td>
                      <td>
                        <%= cond do %>
                          <% is_nil(business.category_fit_score) -> %>
                            <span class="text-base-content/30">-</span>
                          <% Decimal.compare(business.category_fit_score, Decimal.new("0.5")) == :lt -> %>
                            <span class="tooltip" data-tip={business.suggested_category_slug}>
                              <span class="badge badge-error badge-xs">{Decimal.round(business.category_fit_score, 2)}</span>
                            </span>
                          <% true -> %>
                            <span class="badge badge-success badge-xs">{Decimal.round(business.category_fit_score, 2)}</span>
                        <% end %>
                      </td>
                      <td class="text-xs text-base-content/60">
                        {Calendar.strftime(business.inserted_at, "%b %d")}
                      </td>
                      <td>
                        <div class="flex gap-1">
                          <.link navigate={~p"/#{@region_slug}/businesses/#{business.id}"} class="btn btn-ghost btn-xs">
                            View
                          </.link>
                          <.link navigate={~p"/admin/businesses/#{business.id}/edit"} class="btn btn-ghost btn-xs">
                            Edit
                          </.link>
                          <%= if business.status == :pending do %>
                            <button
                              type="button"
                              phx-click="enrich"
                              phx-value-id={business.id}
                              phx-disable-with="..."
                              class="btn btn-primary btn-xs"
                            >
                              Enrich
                            </button>
                          <% end %>
                          <%= if business.category_fit_score && Decimal.compare(business.category_fit_score, Decimal.new("0.5")) == :lt do %>
                            <% suggested_cat = Enum.find(@categories, & &1.slug == business.suggested_category_slug) %>
                            <%= if suggested_cat do %>
                              <form phx-change="move_to_category">
                                <input type="hidden" name="business_id" value={business.id} />
                                <select name="category_id" class="select select-xs select-bordered w-28">
                                  <option value="">Move to...</option>
                                  <option value={suggested_cat.id}>{suggested_cat.name} ✓</option>
                                  <option value="" disabled>———</option>
                                  <%= for cat <- @categories, cat.id != business.category_id do %>
                                    <option value={cat.id}>{cat.name}</option>
                                  <% end %>
                                </select>
                              </form>
                            <% end %>
                            <button
                              type="button"
                              phx-click="reject"
                              phx-value-id={business.id}
                              data-confirm={"Reject #{business.name}?"}
                              class="btn btn-error btn-xs"
                            >
                              Reject
                            </button>
                          <% end %>
                          <button
                            type="button"
                            phx-click="delete"
                            phx-value-id={business.id}
                            data-confirm="Delete this business? This cannot be undone."
                            class="btn btn-ghost btn-xs text-error"
                          >
                            <span class="hero-trash w-3.5 h-3.5"></span>
                          </button>
                        </div>
                      </td>
                    </tr>
                  <% end %>

                  <%= if @page.results == [] do %>
                    <tr>
                      <td colspan="8" class="text-center py-12 text-base-content/50">
                        No businesses found matching your filters.
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          </div>
        </div>

        <!-- Pagination -->
        <% total = total_pages(@page) %>
        <%= if total > 1 do %>
          <% {range_start, range_end} = showing_range(@page, @current_page) %>
          <div class="flex items-center justify-between mt-6">
            <span class="text-sm text-base-content/60">
              Showing {range_start}-{range_end} of {@page.count}
            </span>
            <div class="join">
              <button
                type="button"
                phx-click="page"
                phx-value-page={@current_page - 1}
                class="join-item btn btn-sm"
                disabled={@current_page == 1}
              >
                «
              </button>
              <%= for p <- page_range(@current_page, total) do %>
                <button
                  type="button"
                  phx-click="page"
                  phx-value-page={p}
                  class={["join-item btn btn-sm", if(p == @current_page, do: "btn-active")]}
                >
                  {p}
                </button>
              <% end %>
              <button
                type="button"
                phx-click="page"
                phx-value-page={@current_page + 1}
                class="join-item btn btn-sm"
                disabled={@current_page == total}
              >
                »
              </button>
            </div>
          </div>
        <% end %>

        <!-- Create Modal -->
        <%= if @creating do %>
          <div class="modal modal-open">
            <div class="modal-box max-w-2xl">
              <button type="button" phx-click="cancel" class="btn btn-sm btn-circle btn-ghost absolute right-4 top-4">✕</button>
              <h3 class="font-bold text-lg mb-6">Add Business</h3>
              <form phx-submit="create_business" class="space-y-4">
                <div class="form-control">
                  <label class="label"><span class="label-text font-medium">Name <span class="text-error">*</span></span></label>
                  <input type="text" name="business[name]" class="input input-bordered w-full" required />
                </div>

                <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <div class="form-control">
                    <label class="label"><span class="label-text font-medium">City <span class="text-error">*</span></span></label>
                    <select name="business[city_id]" class="select select-bordered w-full" required>
                      <option value="">Select city...</option>
                      <%= for city <- @cities do %>
                        <option value={city.id}>{city.name}</option>
                      <% end %>
                    </select>
                  </div>
                  <div class="form-control">
                    <label class="label"><span class="label-text font-medium">Category <span class="text-error">*</span></span></label>
                    <select name="business[category_id]" class="select select-bordered w-full" required>
                      <option value="">Select category...</option>
                      <%= for cat <- @categories do %>
                        <option value={cat.id}>{cat.name}</option>
                      <% end %>
                    </select>
                  </div>
                </div>

                <div class="form-control">
                  <label class="label"><span class="label-text font-medium">Address</span></label>
                  <input type="text" name="business[address]" class="input input-bordered w-full" />
                </div>

                <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <div class="form-control">
                    <label class="label"><span class="label-text font-medium">Phone</span></label>
                    <input type="text" name="business[phone]" class="input input-bordered w-full" placeholder="+34 ..." />
                  </div>
                  <div class="form-control">
                    <label class="label"><span class="label-text font-medium">Website</span></label>
                    <input type="url" name="business[website]" class="input input-bordered w-full" placeholder="https://..." />
                  </div>
                </div>

                <p class="text-sm text-base-content/50">
                  The business will be created with "pending" status. You can then enrich it with AI.
                </p>

                <div class="modal-action">
                  <button type="button" phx-click="cancel" class="btn btn-ghost">Cancel</button>
                  <button type="submit" class="btn btn-primary">Create Business</button>
                </div>
              </form>
            </div>
            <div class="modal-backdrop" phx-click="cancel"></div>
          </div>
        <% end %>

        <!-- Edit Modal -->
        <%= if @editing do %>
          <div class="modal modal-open">
            <div class="modal-box max-w-2xl">
              <button type="button" phx-click="cancel" class="btn btn-sm btn-circle btn-ghost absolute right-4 top-4">✕</button>
              <h3 class="font-bold text-lg mb-6">Edit {@editing.name}</h3>
              <form phx-submit="save_business" class="space-y-4">
                <div class="form-control">
                  <label class="label"><span class="label-text font-medium">Name</span></label>
                  <input type="text" name="business[name]" value={@editing.name} class="input input-bordered w-full" />
                </div>

                <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <div class="form-control">
                    <label class="label"><span class="label-text font-medium">City</span></label>
                    <select name="business[city_id]" class="select select-bordered w-full">
                      <%= for city <- @cities do %>
                        <option value={city.id} selected={@editing.city_id == city.id}>{city.name}</option>
                      <% end %>
                    </select>
                  </div>
                  <div class="form-control">
                    <label class="label"><span class="label-text font-medium">Category</span></label>
                    <select name="business[category_id]" class="select select-bordered w-full">
                      <%= for cat <- @categories do %>
                        <option value={cat.id} selected={@editing.category_id == cat.id}>{cat.name}</option>
                      <% end %>
                    </select>
                  </div>
                </div>

                <div class="form-control">
                  <label class="label"><span class="label-text font-medium">Address</span></label>
                  <input type="text" name="business[address]" value={@editing.address} class="input input-bordered w-full" />
                </div>

                <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <div class="form-control">
                    <label class="label"><span class="label-text font-medium">Phone</span></label>
                    <input type="text" name="business[phone]" value={@editing.phone} class="input input-bordered w-full" />
                  </div>
                  <div class="form-control">
                    <label class="label"><span class="label-text font-medium">Website</span></label>
                    <input type="url" name="business[website]" value={@editing.website} class="input input-bordered w-full" />
                  </div>
                </div>

                <div class="form-control">
                  <label class="label"><span class="label-text font-medium">Status</span></label>
                  <select name="business[status]" class="select select-bordered w-full">
                    <option value="pending" selected={@editing.status == :pending}>Pending</option>
                    <option value="researching" selected={@editing.status == :researching}>Researching</option>
                    <option value="researched" selected={@editing.status == :researched}>Researched</option>
                    <option value="enriched" selected={@editing.status == :enriched}>Enriched</option>
                    <option value="verified" selected={@editing.status == :verified}>Verified</option>
                    <option value="rejected" selected={@editing.status == :rejected}>Rejected</option>
                  </select>
                </div>

                <div class="modal-action">
                  <button type="button" phx-click="cancel" class="btn btn-ghost">Cancel</button>
                  <button type="submit" class="btn btn-primary">Save Changes</button>
                </div>
              </form>
            </div>
            <div class="modal-backdrop" phx-click="cancel"></div>
          </div>
        <% end %>
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
