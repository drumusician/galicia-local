defmodule GaliciaLocalWeb.CityLive do
  @moduledoc """
  City detail page showing all businesses in that city.
  """
  use GaliciaLocalWeb, :live_view

  alias GaliciaLocal.Directory.{City, Business, Category}

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case City.get_by_slug(slug) do
      {:ok, city} ->
        city = Ash.load!(city, [:business_count])

        businesses =
          Business.by_city!(city.id)
          |> Ash.load!([:category])

        categories =
          Category.list!()
          |> Enum.sort_by(& &1.priority)

        businesses_by_category =
          businesses
          |> Enum.group_by(& &1.category_id)

        {:ok,
         socket
         |> assign(:page_title, city.name)
         |> assign(:city, city)
         |> assign(:businesses, businesses)
         |> assign(:categories, categories)
         |> assign(:businesses_by_category, businesses_by_category)
         |> assign(:selected_category, nil)
         |> assign(:english_only, false)}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, "City not found")
         |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    category_slug = params["category"]
    english_only = params["english"] == "true"

    selected_category =
      if category_slug do
        Enum.find(socket.assigns.categories, &(&1.slug == category_slug))
      end

    filtered_businesses = filter_businesses(
      socket.assigns.businesses,
      selected_category,
      english_only
    )

    {:noreply,
     socket
     |> assign(:selected_category, selected_category)
     |> assign(:english_only, english_only)
     |> assign(:filtered_businesses, filtered_businesses)}
  end

  @impl true
  def handle_event("filter", params, socket) do
    category_slug = params["category"] || ""
    english = params["english"] == "true"
    url_params = build_params(category_slug, english)
    {:noreply, push_patch(socket, to: ~p"/cities/#{socket.assigns.city.slug}?#{url_params}")}
  end

  defp filter_businesses(businesses, nil, false), do: businesses
  defp filter_businesses(businesses, nil, true) do
    Enum.filter(businesses, & &1.speaks_english)
  end
  defp filter_businesses(businesses, category, false) do
    Enum.filter(businesses, &(&1.category_id == category.id))
  end
  defp filter_businesses(businesses, category, true) do
    Enum.filter(businesses, &(&1.category_id == category.id and &1.speaks_english))
  end

  defp build_params("", false), do: %{}
  defp build_params("", true), do: %{english: true}
  defp build_params(category, false), do: %{category: category}
  defp build_params(category, true), do: %{category: category, english: true}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-100">
      <!-- Hero Banner -->
      <section class="relative h-64 md:h-80">
        <img
          src={@city.image_url || "https://images.unsplash.com/photo-1558618666-fcd25c85cd64?w=1200"}
          alt={@city.name}
          class="w-full h-full object-cover"
        />
        <div class="absolute inset-0 bg-gradient-to-t from-black/70 via-black/30 to-transparent"></div>
        <div class="absolute bottom-0 left-0 right-0 p-8">
          <div class="container mx-auto max-w-6xl">
            <nav class="text-sm breadcrumbs text-white/70 mb-2">
              <ul>
                <li><.link navigate={~p"/"} class="hover:text-white">Home</.link></li>
                <li><.link navigate={~p"/cities"} class="hover:text-white">Cities</.link></li>
                <li class="text-white">{@city.name}</li>
              </ul>
            </nav>
            <h1 class="text-4xl md:text-5xl font-bold text-white mb-2">{@city.name}</h1>
            <p class="text-white/80 text-lg">{@city.province} · {@city.business_count} listings</p>
          </div>
        </div>
      </section>

      <div class="container mx-auto max-w-6xl px-4 py-8">
        <!-- Description -->
        <div class="prose prose-lg max-w-none mb-8">
          <p class="text-base-content/80">{@city.description}</p>
        </div>

        <!-- Filters -->
        <form phx-change="filter" class="flex flex-wrap gap-4 mb-8 items-center">
          <div class="form-control">
            <select
              class="select select-bordered"
              name="category"
            >
              <option value="" selected={@selected_category == nil}>All Categories</option>
              <%= for category <- @categories do %>
                <option
                  value={category.slug}
                  selected={@selected_category && @selected_category.id == category.id}
                >
                  {category.name} ({Map.get(@businesses_by_category, category.id, []) |> length()})
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
                {@business.category.name}
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
