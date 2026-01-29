defmodule GaliciaLocalWeb.CategoryLive do
  @moduledoc """
  Category listing page showing all businesses in that category.
  """
  use GaliciaLocalWeb, :live_view

  alias GaliciaLocal.Directory.{Category, Business, City}

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case Category.get_by_slug(slug) do
      {:ok, category} ->
        category = Ash.load!(category, [:business_count])

        businesses =
          Business.by_category!(category.id)
          |> Ash.load!([:city])

        cities =
          City.list!()
          |> Enum.sort_by(& &1.name)

        {:ok,
         socket
         |> assign(:page_title, category.name)
         |> assign(:category, category)
         |> assign(:businesses, businesses)
         |> assign(:cities, cities)
         |> assign(:selected_city, nil)
         |> assign(:english_only, false)
         |> assign(:filtered_businesses, businesses)}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, "Category not found")
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

    filtered_businesses = filter_businesses(
      socket.assigns.businesses,
      selected_city,
      english_only
    )

    {:noreply,
     socket
     |> assign(:selected_city, selected_city)
     |> assign(:english_only, english_only)
     |> assign(:filtered_businesses, filtered_businesses)}
  end

  @impl true
  def handle_event("filter", params, socket) do
    city_slug = Map.get(params, "city", "")
    english = Map.get(params, "english") == "true"
    params = build_params(city_slug, english)
    {:noreply, push_patch(socket, to: ~p"/categories/#{socket.assigns.category.slug}?#{params}")}
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

  defp build_params("", false), do: %{}
  defp build_params("", true), do: %{english: true}
  defp build_params(city, false), do: %{city: city}
  defp build_params(city, true), do: %{city: city, english: true}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-100">
      <div class="container mx-auto max-w-6xl px-4 py-8">
        <!-- Breadcrumbs -->
        <nav class="text-sm breadcrumbs mb-6">
          <ul>
            <li><.link navigate={~p"/"} class="hover:text-primary">Home</.link></li>
            <li><.link navigate={~p"/categories"} class="hover:text-primary">Categories</.link></li>
            <li class="text-base-content/60">{@category.name}</li>
          </ul>
        </nav>

        <!-- Header -->
        <div class="mb-8">
          <div class="flex items-center gap-4 mb-4">
            <div class="w-16 h-16 rounded-full bg-primary/10 flex items-center justify-center">
              <span class={"hero-#{@category.icon || "building-storefront"} w-8 h-8 text-primary"}></span>
            </div>
            <div>
              <h1 class="text-3xl font-bold text-base-content">{@category.name}</h1>
              <p class="text-base-content/60">{@category.name_es}</p>
            </div>
          </div>
          <%= if @category.description do %>
            <p class="text-base-content/70">{@category.description}</p>
          <% end %>
        </div>

        <!-- Filters -->
        <form phx-change="filter" class="flex flex-wrap gap-4 mb-8 items-center">
          <div class="form-control">
            <select
              class="select select-bordered"
              name="city"
            >
              <option value="" selected={@selected_city == nil}>All Cities</option>
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
            <span class="label-text">English speaking only</span>
          </label>

          <div class="flex-1"></div>

          <span class="text-sm text-base-content/60">
            {length(@filtered_businesses)} results
          </span>
        </form>

        <!-- Business List -->
        <%= if length(@filtered_businesses) > 0 do %>
          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            <%= for business <- @filtered_businesses do %>
              <.business_card business={business} />
            <% end %>
          </div>
        <% else %>
          <div class="text-center py-20">
            <div class="text-6xl mb-4">🔍</div>
            <h3 class="text-xl font-semibold mb-2">No businesses found</h3>
            <p class="text-base-content/60">
              Try adjusting your filters or check back later.
            </p>
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
            <%= if @business.speaks_english do %>
              <div class="tooltip" data-tip="English spoken">
                <span class="badge badge-success">EN</span>
              </div>
            <% end %>
          </div>

          <p class="text-sm text-base-content/70 line-clamp-2 mt-2">
            {@business.summary || @business.description}
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
            <div class="flex flex-wrap gap-1 mt-2">
              <%= for highlight <- Enum.take(@business.highlights, 2) do %>
                <span class="badge badge-ghost badge-xs">{highlight}</span>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
    </.link>
    """
  end
end
