defmodule GaliciaLocalWeb.CategoryLive do
  @moduledoc """
  Category listing page showing all businesses in that category.
  """
  use GaliciaLocalWeb, :live_view

  alias GaliciaLocal.Directory.{Category, Business, City}
  alias GaliciaLocal.Analytics.Tracker

  @per_page 24

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    region = socket.assigns[:current_region]
    region_slug = if region, do: region.slug, else: "galicia"
    region_name = if region, do: Gettext.gettext(GaliciaLocalWeb.Gettext, region.name), else: gettext("Galicia")
    tenant_opts = if region, do: [tenant: region.id], else: []

    case Category.get_by_slug(slug) do
      {:ok, category} ->
        category = Ash.load!(category, [:translations])
        if connected?(socket) and region, do: Tracker.track_async("category", category.id, region.id)

        businesses =
          Business.by_category!(category.id, tenant_opts)
          |> Ash.load!([:city])

        cities =
          City.list!(tenant_opts)
          |> Enum.sort_by(& &1.name)

        {:ok,
         socket
         |> assign(:page_title, category.name)
         |> assign(:meta_description, category.description || gettext("Find the best %{category} in %{region}. Browse local listings with reviews, ratings, and insider tips.", category: category.name, region: region_name))
         |> assign(:category, category)
         |> assign(:businesses, businesses)
         |> assign(:cities, cities)
         |> assign(:selected_city, nil)
         |> assign(:english_only, false)
         |> assign(:user_location, nil)
         |> assign(:map_bounds, nil)
         |> assign(:filtered_businesses, businesses)
         |> assign(:page, 1)
         |> assign(:region_slug, region_slug)}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Category not found"))
         |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    city_slug = params["city"]
    english_only = params["english"] == "true"

    selected_city =
      if city_slug do
        Enum.find(socket.assigns.cities, &(&1.slug == city_slug))
      end

    filtered = filter_businesses(
      socket.assigns.businesses,
      selected_city,
      english_only
    )

    filtered = maybe_sort_by_distance(filtered, socket.assigns.user_location)

    map_businesses = filter_businesses(socket.assigns.businesses, selected_city, english_only)
    displayed = Enum.take(filtered, @per_page)

    {:noreply,
     socket
     |> assign(:selected_city, selected_city)
     |> assign(:english_only, english_only)
     |> assign(:map_bounds, nil)
     |> assign(:filtered_businesses, filtered)
     |> assign(:page, 1)
     |> assign(:displayed_businesses, displayed)
     |> assign(:has_more, length(filtered) > @per_page)
     |> push_event("update-markers", %{businesses: businesses_list(map_businesses)})}
  end

  @impl true
  def handle_event("load-more", _params, socket) do
    page = socket.assigns.page + 1
    displayed = Enum.take(socket.assigns.filtered_businesses, page * @per_page)
    has_more = length(socket.assigns.filtered_businesses) > page * @per_page

    {:noreply,
     socket
     |> assign(:page, page)
     |> assign(:displayed_businesses, displayed)
     |> assign(:has_more, has_more)}
  end

  @impl true
  def handle_event("filter", params, socket) do
    city_slug = Map.get(params, "city", "")
    english = Map.get(params, "english") == "true"
    url_params = build_params(city_slug, english)
    region_slug = socket.assigns.region_slug
    {:noreply, push_patch(socket, to: ~p"/#{region_slug}/categories/#{socket.assigns.category.slug}?#{url_params}")}
  end

  @impl true
  def handle_event("user_location", %{"lat" => lat, "lng" => lng}, socket) do
    location = {lat, lng}

    filtered =
      filter_businesses(
        socket.assigns.businesses,
        socket.assigns.selected_city,
        socket.assigns.english_only
      )
      |> maybe_sort_by_distance(location)

    {:noreply,
     socket
     |> assign(:user_location, location)
     |> assign(:filtered_businesses, filtered)
     |> assign(:page, 1)
     |> assign(:displayed_businesses, Enum.take(filtered, @per_page))
     |> assign(:has_more, length(filtered) > @per_page)}
  end

  @impl true
  def handle_event("map_bounds", %{"south" => s, "north" => n, "west" => w, "east" => e}, socket) do
    bounds = %{south: s, north: n, west: w, east: e}

    filtered =
      filter_businesses(
        socket.assigns.businesses,
        socket.assigns.selected_city,
        socket.assigns.english_only
      )
      |> filter_by_bounds(bounds)
      |> maybe_sort_by_distance(socket.assigns.user_location)

    {:noreply,
     socket
     |> assign(:map_bounds, bounds)
     |> assign(:filtered_businesses, filtered)
     |> assign(:page, 1)
     |> assign(:displayed_businesses, Enum.take(filtered, @per_page))
     |> assign(:has_more, length(filtered) > @per_page)}
  end

  @impl true
  def handle_event("reset_bounds", _params, socket) do
    filtered =
      filter_businesses(
        socket.assigns.businesses,
        socket.assigns.selected_city,
        socket.assigns.english_only
      )
      |> maybe_sort_by_distance(socket.assigns.user_location)

    {:noreply,
     socket
     |> assign(:map_bounds, nil)
     |> assign(:filtered_businesses, filtered)
     |> assign(:page, 1)
     |> assign(:displayed_businesses, Enum.take(filtered, @per_page))
     |> assign(:has_more, length(filtered) > @per_page)}
  end

  @impl true
  def handle_event("location_error", _params, socket) do
    {:noreply, socket}
  end

  defp filter_businesses(businesses, nil, false), do: businesses
  defp filter_businesses(businesses, nil, true) do
    Enum.filter(businesses, & &1.speaks_english)
  end
  defp filter_businesses(businesses, city, false) do
    Enum.filter(businesses, &(&1.city_id == city.id))
  end
  defp filter_businesses(businesses, city, true) do
    Enum.filter(businesses, &(&1.city_id == city.id and &1.speaks_english))
  end

  defp filter_by_bounds(businesses, nil), do: businesses
  defp filter_by_bounds(businesses, %{south: s, north: n, west: w, east: e}) do
    Enum.filter(businesses, fn biz ->
      if biz.latitude && biz.longitude do
        lat = Decimal.to_float(biz.latitude)
        lng = Decimal.to_float(biz.longitude)
        lat >= s and lat <= n and lng >= w and lng <= e
      else
        true
      end
    end)
  end

  defp maybe_sort_by_distance(businesses, nil), do: businesses
  defp maybe_sort_by_distance(businesses, {user_lat, user_lng}) do
    Enum.sort_by(businesses, fn biz ->
      if biz.latitude && biz.longitude do
        haversine(user_lat, user_lng, Decimal.to_float(biz.latitude), Decimal.to_float(biz.longitude))
      else
        999_999
      end
    end)
  end

  defp haversine(lat1, lng1, lat2, lng2) do
    r = 6371
    dlat = deg_to_rad(lat2 - lat1)
    dlng = deg_to_rad(lng2 - lng1)
    a = :math.sin(dlat / 2) * :math.sin(dlat / 2) +
        :math.cos(deg_to_rad(lat1)) * :math.cos(deg_to_rad(lat2)) *
        :math.sin(dlng / 2) * :math.sin(dlng / 2)
    2 * r * :math.asin(:math.sqrt(a))
  end

  defp deg_to_rad(deg), do: deg * :math.pi() / 180

  defp distance_for(_business, nil), do: nil
  defp distance_for(business, {user_lat, user_lng}) do
    if business.latitude && business.longitude do
      km = haversine(user_lat, user_lng, Decimal.to_float(business.latitude), Decimal.to_float(business.longitude))
      Float.round(km, 1)
    end
  end

  defp build_params("", false), do: %{}
  defp build_params("", true), do: %{english: true}
  defp build_params(city, false), do: %{city: city}
  defp build_params(city, true), do: %{city: city, english: true}

  defp businesses_list(businesses) do
    businesses
    |> Enum.filter(&(&1.latitude && &1.longitude))
    |> Enum.map(fn biz ->
      %{
        id: biz.id,
        name: biz.name,
        lat: Decimal.to_float(biz.latitude),
        lng: Decimal.to_float(biz.longitude),
        city: biz.city.name,
        address: biz.address
      }
    end)
  end

  defp businesses_json(businesses) do
    businesses |> businesses_list() |> Jason.encode!()
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :businesses_json, businesses_json(assigns.businesses))
    has_coords = Enum.any?(assigns.businesses, &(&1.latitude && &1.longitude))
    assigns = assign(assigns, :has_coords, has_coords)

    ~H"""
    <div class="min-h-screen bg-base-100">
      <div class="container mx-auto max-w-6xl px-4 py-8">
        <!-- Breadcrumbs -->
        <nav class="text-sm breadcrumbs mb-6">
          <ul>
            <li><.link navigate={~p"/#{@region_slug}"} class="hover:text-primary">{gettext("Home")}</.link></li>
            <li><.link navigate={~p"/#{@region_slug}/categories"} class="hover:text-primary">{gettext("Categories")}</.link></li>
            <li class="text-base-content/60">{localized_name(@category, @locale)}</li>
          </ul>
        </nav>

        <!-- Header -->
        <div class="mb-8">
          <div class="flex items-center gap-4 mb-4">
            <div class="w-16 h-16 rounded-full bg-primary/10 flex items-center justify-center">
              <span class={"hero-#{@category.icon || "building-storefront"} w-8 h-8 text-primary"}></span>
            </div>
            <div>
              <h1 class="text-3xl font-bold text-base-content">{localized_name(@category, @locale)}</h1>
              <% secondary = localized_name(@category, "es") %>
              <%= if secondary != localized_name(@category, @locale) do %>
                <p class="text-base-content/60">{secondary}</p>
              <% end %>
            </div>
          </div>
          <%= if @category.description do %>
            <p class="text-base-content/70">{@category.description}</p>
          <% end %>
        </div>

        <!-- Filters -->
        <form phx-change="filter" class="flex flex-wrap gap-4 mb-6 items-center">
          <div class="form-control">
            <select
              class="select select-bordered"
              name="city"
            >
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

          <label class="label cursor-pointer gap-2">
            <input
              type="checkbox"
              name="english"
              value="true"
              checked={@english_only}
              class="checkbox checkbox-primary"
            />
            <span class="label-text">{gettext("English speaking only")}</span>
          </label>

          <button
            type="button"
            id="geolocate-btn"
            phx-hook="GeoLocate"
            class={["btn btn-sm btn-outline gap-1", @user_location && "btn-info"]}
          >
            <span class="hero-map-pin w-4 h-4"></span>
            <%= if @user_location, do: gettext("Near me ✓"), else: gettext("Near me") %>
          </button>

          <div class="flex-1"></div>

          <%= if @map_bounds do %>
            <button type="button" phx-click="reset_bounds" class="btn btn-sm btn-ghost gap-1 text-warning">
              <span class="hero-x-mark w-4 h-4"></span>
              {gettext("Show all")}
            </button>
          <% end %>

          <span class="text-sm text-base-content/60">
            {ngettext("1 result", "%{count} results", length(@filtered_businesses))}
            <%= if @map_bounds do %>
              <span class="text-warning">{gettext("(map area)")}</span>
            <% end %>
          </span>
        </form>

        <!-- Map -->
        <%= if @has_coords do %>
          <div
            id="category-map"
            class="h-64 bg-base-200 rounded-lg mb-8"
            phx-hook="BusinessesMap"
            phx-update="ignore"
            data-businesses={@businesses_json}
            data-region={@region_slug}
            data-user-lat={@user_location && elem(@user_location, 0)}
            data-user-lng={@user_location && elem(@user_location, 1)}
          >
            <div class="flex items-center justify-center h-full text-base-content/40">
              {gettext("Loading map...")}
            </div>
          </div>
        <% end %>

        <!-- Business List -->
        <%= if length(@filtered_businesses) > 0 do %>
          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            <%= for business <- @displayed_businesses do %>
              <.business_card business={business} distance={distance_for(business, @user_location)} region_slug={@region_slug} />
            <% end %>
          </div>
          <%= if @has_more do %>
            <div id="infinite-scroll-sentinel" phx-hook="InfiniteScroll" class="flex justify-center py-8">
              <span class="loading loading-spinner loading-md text-primary"></span>
            </div>
          <% end %>
        <% else %>
          <div class="text-center py-20">
            <div class="text-6xl mb-4">🔍</div>
            <h3 class="text-xl font-semibold mb-2">{gettext("No businesses found")}</h3>
            <p class="text-base-content/60">
              {gettext("Try adjusting your filters or check back later.")}
            </p>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  attr :business, :map, required: true
  attr :distance, :float, default: nil
  attr :region_slug, :string, default: "galicia"
  defp business_card(assigns) do
    ~H"""
    <.link navigate={~p"/#{@region_slug}/businesses/#{@business.id}"} class="group">
      <div class="card bg-base-100 border border-base-300 hover:border-primary hover:shadow-lg transition-all">
        <div class="card-body">
          <div class="flex justify-between items-start">
            <div>
              <h3 class="card-title text-lg group-hover:text-primary transition-colors">
                {@business.name}
              </h3>
              <p class="text-sm text-base-content/60">
                {@business.city.name}
              </p>
            </div>
            <div class="flex items-center gap-1">
              <%= if @distance do %>
                <span class="badge badge-info badge-sm">{@distance} km</span>
              <% end %>
              <%= if @business.speaks_english do %>
                <div class="tooltip" data-tip={gettext("English spoken")}>
                  <span class="badge badge-success">{gettext("EN")}</span>
                </div>
              <% end %>
            </div>
          </div>

          <p class="text-sm text-base-content/70 line-clamp-2 mt-2">
            {@business.summary || localized(@business, :description, assigns[:locale] || "en")}
          </p>

          <%= if @business.address do %>
            <p class="text-xs text-base-content/50 mt-2 flex items-center gap-1">
              <span class="hero-map-pin w-4 h-4"></span>
              {@business.address}
            </p>
          <% end %>

          <div class="flex items-center justify-between mt-4">
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

          <%= if length(@business.highlights || []) > 0 do %>
            <div class="bg-base-200 rounded-lg px-3 py-2 mt-3 space-y-0.5">
              <%= for highlight <- Enum.take(@business.highlights, 2) do %>
                <p class="text-xs text-base-content/60">{highlight}</p>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
    </.link>
    """
  end
end
