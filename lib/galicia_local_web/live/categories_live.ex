defmodule GaliciaLocalWeb.CategoriesLive do
  @moduledoc """
  Categories index page showing all categories organized by priority.
  """
  use GaliciaLocalWeb, :live_view

  alias GaliciaLocal.Directory.Category

  @impl true
  def mount(_params, _session, socket) do
    region = socket.assigns[:current_region]
    region_slug = if region, do: region.slug, else: "galicia"
    region_name = if region, do: Gettext.gettext(GaliciaLocalWeb.Gettext, region.name), else: gettext("Galicia")
    locale = socket.assigns[:locale] || "en"

    # Get business counts per category for this region
    business_counts = get_business_counts_by_category(region)

    categories =
      Category.list!()
      |> Ash.load!([:translations])
      |> Enum.map(fn cat ->
        Map.put(cat, :business_count, Map.get(business_counts, cat.id, 0))
      end)
      |> Enum.group_by(& &1.priority)
      |> Enum.sort_by(fn {priority, _} -> priority end)

    {:ok,
     socket
     |> assign(:page_title, gettext("Browse by Category"))
     |> assign(:meta_description, gettext("Browse local businesses in %{region} by category. From restaurants and legal help to healthcare and education – find what you need.", region: region_name))
     |> assign(:categories_by_priority, categories)
     |> assign(:region_slug, region_slug)
     |> assign(:locale, locale)}
  end

  defp get_business_counts_by_category(nil), do: %{}
  defp get_business_counts_by_category(region) do
    import Ecto.Query

    GaliciaLocal.Repo.all(
      from b in "businesses",
        where: b.region_id == type(^region.id, Ecto.UUID),
        where: b.status in ["enriched", "verified"],
        group_by: b.category_id,
        select: {type(b.category_id, :binary_id), count(b.id)}
    )
    |> Enum.into(%{})
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-100">
      <div class="container mx-auto max-w-6xl px-4 py-8">
        <!-- Header -->
        <div class="text-center mb-12">
          <h1 class="text-4xl font-bold text-base-content mb-4">{gettext("Browse Categories")}</h1>
          <p class="text-base-content/70 max-w-2xl mx-auto">
            {gettext("Find exactly what you need, from essential expat services to local lifestyle experiences.")}
          </p>
        </div>

        <!-- Categories by Priority -->
        <%= for {priority, categories} <- @categories_by_priority do %>
          <div class="mb-12">
            <div class="flex items-center gap-4 mb-6">
              <h2 class="text-2xl font-bold text-base-content">{priority_label(priority)}</h2>
              <span class={"badge badge-lg #{priority_badge_class(priority)}"}>
                {gettext("Priority %{number}", number: priority)}
              </span>
            </div>
            <p class="text-base-content/60 mb-6">{priority_description(priority)}</p>

            <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
              <%= for category <- categories do %>
                <.link navigate={~p"/#{@region_slug}/categories/#{category.slug}"} class="group">
                  <div class="card bg-base-100 border border-base-300 hover:border-primary hover:shadow-lg transition-all">
                    <div class="card-body flex-row items-center gap-4">
                      <div class={"w-14 h-14 rounded-full flex items-center justify-center flex-shrink-0 #{priority_bg_class(priority)}"}>
                        <span class={"hero-#{category.icon || "building-storefront"} w-7 h-7"}></span>
                      </div>
                      <div class="flex-1 min-w-0">
                        <h3 class="font-semibold text-lg group-hover:text-primary transition-colors">
                          {category_name(category, @locale)}
                        </h3>
                        <p class="text-sm text-base-content/60">{secondary_name(category, @locale)}</p>
                        <p class="text-xs text-base-content/50 mt-1 truncate">
                          {category_description(category, @locale)}
                        </p>
                      </div>
                      <div class="flex flex-col items-end">
                        <span class="badge badge-primary">{category.business_count || 0}</span>
                        <span class="text-xs text-base-content/50 mt-1">{gettext("listings")}</span>
                      </div>
                    </div>
                  </div>
                </.link>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp priority_label(1), do: gettext("Expat Essentials")
  defp priority_label(2), do: gettext("Daily Life")
  defp priority_label(3), do: gettext("Lifestyle & Culture")
  defp priority_label(4), do: gettext("Practical Services")
  defp priority_label(_), do: gettext("Other")

  defp priority_description(1), do: gettext("Essential services for expats and newcomers - lawyers, doctors, real estate, and more.")
  defp priority_description(2), do: gettext("Everyday essentials - groceries, markets, and personal services.")
  defp priority_description(3), do: gettext("Experience the best of Galicia - restaurants, wineries, and cultural spots.")
  defp priority_description(4), do: gettext("Practical services for your home and car.")
  defp priority_description(_), do: ""

  defp priority_badge_class(1), do: "badge-primary"
  defp priority_badge_class(2), do: "badge-secondary"
  defp priority_badge_class(3), do: "badge-accent"
  defp priority_badge_class(4), do: "badge-neutral"
  defp priority_badge_class(_), do: "badge-ghost"

  defp priority_bg_class(1), do: "bg-primary/10 text-primary"
  defp priority_bg_class(2), do: "bg-secondary/10 text-secondary"
  defp priority_bg_class(3), do: "bg-accent/10 text-accent"
  defp priority_bg_class(4), do: "bg-neutral/10 text-neutral"
  defp priority_bg_class(_), do: "bg-base-200"

  # Localization helpers
  defp category_name(category, locale) do
    case get_translation(category, locale) do
      %{name: name} when is_binary(name) and name != "" -> name
      _ -> category.name
    end
  end

  defp secondary_name(category, "en"), do: category.name_es || ""
  defp secondary_name(category, _locale), do: category.name

  defp category_description(category, locale) do
    case get_translation(category, locale) do
      %{description: desc} when is_binary(desc) and desc != "" -> desc
      _ -> category.description
    end
  end

  defp get_translation(category, locale) do
    Enum.find(category.translations || [], fn t -> t.locale == locale end)
  end
end
