defmodule GaliciaLocalWeb.SearchLive do
  @moduledoc """
  Search page for finding businesses across all cities and categories.
  """
  use GaliciaLocalWeb, :live_view

  require Ash.Query

  alias GaliciaLocal.Directory.{Business, City, Category}

  @impl true
  def mount(_params, _session, socket) do
    cities = City.list!() |> Enum.sort_by(& &1.name)
    categories = Category.list!() |> Enum.sort_by(& &1.priority)

    {:ok,
     socket
     |> assign(:page_title, gettext("Search"))
     |> assign(:cities, cities)
     |> assign(:categories, categories)
     |> assign(:results, [])
     |> assign(:query, "")
     |> assign(:selected_city, nil)
     |> assign(:selected_category, nil)
     |> assign(:english_only, false)
     |> assign(:local_gems, false)
     |> assign(:loading, false)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    query = params["q"] || ""
    filter = params["filter"]
    english_only = filter == "english" || params["english"] == "true"
    local_gems = filter == "local-gems"
    city_slug = params["city"]
    category_slug = params["category"]

    selected_city = if city_slug, do: Enum.find(socket.assigns.cities, &(&1.slug == city_slug))
    selected_category = if category_slug, do: Enum.find(socket.assigns.categories, &(&1.slug == category_slug))

    results = search_businesses(query, selected_city, selected_category, english_only, local_gems)

    {:noreply,
     socket
     |> assign(:query, query)
     |> assign(:english_only, english_only)
     |> assign(:local_gems, local_gems)
     |> assign(:selected_city, selected_city)
     |> assign(:selected_category, selected_category)
     |> assign(:results, results)}
  end

  @impl true
  def handle_event("search", %{"query" => query} = params, socket) do
    city = params["city"] || ""
    category = params["category"] || ""
    english = params["english"] == "true"

    query_params = build_query_params(query, city, category, english)
    {:noreply, push_patch(socket, to: ~p"/search?#{query_params}")}
  end

  @impl true
  def handle_event("filter", params, socket) do
    city = params["city"] || ""
    category = params["category"] || ""
    english = params["english"] == "true"

    query_params = build_query_params(socket.assigns.query, city, category, english)
    {:noreply, push_patch(socket, to: ~p"/search?#{query_params}")}
  end

  defp build_query_params(query, city, category, english) do
    %{}
    |> maybe_add("q", query)
    |> maybe_add("city", city)
    |> maybe_add("category", category)
    |> maybe_add_bool("english", english)
  end

  defp maybe_add(params, _key, ""), do: params
  defp maybe_add(params, _key, nil), do: params
  defp maybe_add(params, key, value), do: Map.put(params, key, value)

  defp maybe_add_bool(params, _key, false), do: params
  defp maybe_add_bool(params, key, true), do: Map.put(params, key, "true")

  defp search_businesses(query, city, category, english_only, local_gems) do
    cond do
      String.trim(query) != "" ->
        Business.search!(query)
        |> filter_by_city(city)
        |> filter_by_category(category)
        |> filter_by_english(english_only)
        |> filter_by_local_gems(local_gems)
        |> Ash.load!([:city, :category])

      english_only ->
        Business.english_speaking!()
        |> filter_by_city(city)
        |> filter_by_category(category)
        |> filter_by_local_gems(local_gems)
        |> Ash.load!([:city, :category])

      local_gems ->
        Business
        |> Ash.Query.for_read(:read)
        |> Ash.Query.filter(status in [:enriched, :verified])
        |> Ash.Query.filter(local_gem_score > 0.7)
        |> filter_by_city_query(city)
        |> filter_by_category_query(category)
        |> Ash.Query.sort(local_gem_score: :desc, rating: :desc_nils_last)
        |> Ash.Query.limit(50)
        |> Ash.Query.load([:city, :category])
        |> Ash.read!()

      true ->
        Business
        |> Ash.Query.for_read(:read)
        |> Ash.Query.filter(status in [:enriched, :verified])
        |> filter_by_city_query(city)
        |> filter_by_category_query(category)
        |> Ash.Query.sort(rating: :desc_nils_last, name: :asc)
        |> Ash.Query.limit(50)
        |> Ash.Query.load([:city, :category])
        |> Ash.read!()
    end
  end

  defp filter_by_city(results, nil), do: results
  defp filter_by_city(results, city), do: Enum.filter(results, &(&1.city_id == city.id))

  defp filter_by_category(results, nil), do: results
  defp filter_by_category(results, category), do: Enum.filter(results, &(&1.category_id == category.id))

  defp filter_by_english(results, false), do: results
  defp filter_by_english(results, true), do: Enum.filter(results, & &1.speaks_english)

  defp filter_by_local_gems(results, false), do: results
  defp filter_by_local_gems(results, true) do
    Enum.filter(results, fn b ->
      b.local_gem_score && Decimal.compare(b.local_gem_score, Decimal.new("0.7")) == :gt
    end)
  end

  defp filter_by_city_query(query, nil), do: query
  defp filter_by_city_query(query, city), do: Ash.Query.filter(query, city_id: city.id)

  defp filter_by_category_query(query, nil), do: query
  defp filter_by_category_query(query, category), do: Ash.Query.filter(query, category_id: category.id)

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-100">
      <div class="container mx-auto max-w-6xl px-4 py-8">
        <!-- Header -->
        <div class="mb-8">
          <h1 class="text-3xl font-bold text-base-content mb-2">{gettext("Search Businesses")}</h1>
          <p class="text-base-content/60">
            {gettext("Find services and businesses across Galicia")}
          </p>
        </div>

        <!-- Search & Filters -->
        <div class="card bg-base-200 mb-8">
          <div class="card-body">
            <form phx-submit="search" phx-change="filter" class="space-y-4">
              <div class="form-control">
                <div class="join w-full">
                  <input
                    type="text"
                    name="query"
                    value={@query}
                    placeholder={gettext("Search for businesses, services...")}
                    class="input input-bordered join-item flex-1"
                    phx-debounce="300"
                  />
                  <button type="submit" class="btn btn-primary join-item">
                    <span class="hero-magnifying-glass w-5 h-5"></span>
                    {gettext("Search")}
                  </button>
                </div>
              </div>

              <div class="flex flex-wrap gap-4">
                <div class="form-control">
                  <select name="city" class="select select-bordered select-sm">
                    <option value="" selected={@selected_city == nil}>{gettext("All Cities")}</option>
                    <%= for city <- @cities do %>
                      <option
                        value={city.slug}
                        selected={@selected_city && @selected_city.id == city.id}
                      >
                        {city.name}
                      </option>
                    <% end %>
                  </select>
                </div>

                <div class="form-control">
                  <select name="category" class="select select-bordered select-sm">
                    <option value="" selected={@selected_category == nil}>{gettext("All Categories")}</option>
                    <%= for category <- @categories do %>
                      <option
                        value={category.slug}
                        selected={@selected_category && @selected_category.id == category.id}
                      >
                        {localized_name(category, @locale)}
                      </option>
                    <% end %>
                  </select>
                </div>

                <label class="label cursor-pointer gap-2">
                  <input
                    type="checkbox"
                    name="english"
                    value="true"
                    checked={@english_only}
                    class="checkbox checkbox-primary checkbox-sm"
                  />
                  <span class="label-text">{gettext("English speaking only")}</span>
                </label>
              </div>
            </form>
          </div>
        </div>

        <!-- Results -->
        <div class="mb-4 flex justify-between items-center">
          <span class="text-sm text-base-content/60">
            {ngettext("1 result", "%{count} results", length(@results))}
            <%= if @english_only do %>
              <span class="badge badge-success badge-sm ml-2">{gettext("English speaking")}</span>
            <% end %>
            <%= if @local_gems do %>
              <span class="badge badge-warning badge-sm ml-2">{gettext("Local Gems")}</span>
            <% end %>
          </span>
        </div>

        <%= if length(@results) > 0 do %>
          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            <%= for business <- @results do %>
              <.business_card business={business} />
            <% end %>
          </div>
        <% else %>
          <div class="text-center py-20">
            <div class="text-6xl mb-4">🔍</div>
            <h3 class="text-xl font-semibold mb-2">{gettext("No results found")}</h3>
            <p class="text-base-content/60 mb-4">
              {gettext("Try different search terms or adjust your filters.")}
            </p>
            <%= if @english_only do %>
              <button
                type="button"
                phx-click="filter"
                phx-value-city={if @selected_city, do: @selected_city.slug, else: ""}
                phx-value-category={if @selected_category, do: @selected_category.slug, else: ""}
                phx-value-english="false"
                class="btn btn-outline btn-sm"
              >
                {gettext("Remove English filter")}
              </button>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  attr :business, :map, required: true
  defp business_card(assigns) do
    ~H"""
    <.link navigate={~p"/businesses/#{@business.id}"} class="group">
      <div class="card bg-base-100 border border-base-300 hover:border-primary hover:shadow-lg transition-all h-full">
        <div class="card-body">
          <div class="flex justify-between items-start">
            <div>
              <h3 class="card-title text-lg group-hover:text-primary transition-colors">
                {@business.name}
              </h3>
              <p class="text-sm text-base-content/60">
                {@business.city.name} · {localized_name(@business.category, assigns[:locale] || "en")}
              </p>
            </div>
            <%= if @business.speaks_english do %>
              <div class="tooltip" data-tip={gettext("English spoken")}>
                <span class="badge badge-success">{gettext("EN")}</span>
              </div>
            <% end %>
          </div>

          <p class="text-sm text-base-content/70 line-clamp-2 mt-2">
            {@business.summary || localized(@business, :description, assigns[:locale] || "en")}
          </p>

          <%= if @business.address do %>
            <p class="text-xs text-base-content/50 mt-2 flex items-center gap-1">
              <span class="hero-map-pin w-4 h-4"></span>
              <span class="truncate">{@business.address}</span>
            </p>
          <% end %>

          <div class="flex items-center justify-between mt-auto pt-4">
            <div class="flex items-center gap-1">
              <%= if @business.rating do %>
                <span class="text-warning">★</span>
                <span class="text-sm font-medium">{Decimal.round(@business.rating, 1)}</span>
                <span class="text-xs text-base-content/50">
                  ({@business.review_count})
                </span>
              <% end %>
            </div>
            <%= if @business.price_level do %>
              <span class="text-sm text-base-content/60">
                {String.duplicate("€", @business.price_level)}
              </span>
            <% end %>
          </div>
        </div>
      </div>
    </.link>
    """
  end
end
