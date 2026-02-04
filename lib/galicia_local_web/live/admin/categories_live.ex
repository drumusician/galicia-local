defmodule GaliciaLocalWeb.Admin.CategoriesLive do
  @moduledoc """
  Admin interface for managing categories.
  """
  use GaliciaLocalWeb, :live_view

  alias GaliciaLocal.Directory.Category

  @supported_locales ["en", "es", "nl"]

  @impl true
  def mount(_params, _session, socket) do
    region = socket.assigns[:current_region]
    region_slug = if region, do: region.slug, else: "galicia"

    {:ok,
     socket
     |> assign(:page_title, "Manage Categories")
     |> assign(:region_slug, region_slug)
     |> assign(:categories, load_categories())
     |> assign(:creating, false)
     |> assign(:supported_locales, @supported_locales)}
  end

  defp load_categories do
    Category.list!()
    |> Ash.load!([:business_count, :translations])
    |> Enum.sort_by(& &1.priority)
  end

  defp get_translation(category, locale) do
    Enum.find(category.translations, fn t -> t.locale == locale end)
  end

  defp locale_flag("en"), do: "🇬🇧"
  defp locale_flag("es"), do: "🇪🇸"
  defp locale_flag("nl"), do: "🇳🇱"
  defp locale_flag(_), do: "🌐"

  @impl true
  def handle_event("new", _params, socket) do
    {:noreply, assign(socket, :creating, true)}
  end

  @impl true
  def handle_event("cancel", _params, socket) do
    {:noreply, assign(socket, :creating, false)}
  end

  @impl true
  def handle_event("create", %{"category" => params}, socket) do
    # Auto-generate slug from name if not provided
    params =
      if params["slug"] in [nil, ""] do
        Map.put(params, "slug", Slug.slugify(params["name"] || ""))
      else
        params
      end

    case Category.create(params) do
      {:ok, category} ->
        {:noreply,
         socket
         |> assign(:categories, load_categories())
         |> assign(:creating, false)
         |> put_flash(:info, "Category created successfully")
         |> push_navigate(to: ~p"/admin/categories/#{category.id}/edit")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create category")}
    end
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
              <h1 class="text-2xl font-bold">Manage Categories</h1>
            </div>
            <button type="button" phx-click="new" class="btn btn-primary btn-sm">
              <span class="hero-plus w-4 h-4"></span>
              Add Category
            </button>
          </div>
        </div>
      </header>

      <main class="container mx-auto px-6 py-8">
        <div class="card bg-base-100 shadow-xl">
          <div class="card-body p-0">
            <div class="overflow-x-auto">
              <table class="table">
                <thead>
                  <tr>
                    <th>Icon</th>
                    <th>Name</th>
                    <th>Businesses</th>
                    <th>Priority</th>
                    <th>Translations</th>
                    <th></th>
                  </tr>
                </thead>
                <tbody>
                  <%= for category <- @categories do %>
                    <tr class="hover">
                      <td>
                        <span class={"hero-#{category.icon} w-6 h-6 inline-block text-primary"}></span>
                      </td>
                      <td>
                        <div class="font-medium">{category.name}</div>
                        <div class="text-sm text-base-content/50">{category.slug}</div>
                      </td>
                      <td>
                        <span class="badge badge-primary">{category.business_count}</span>
                      </td>
                      <td>
                        <span class={[
                          "badge badge-sm",
                          priority_class(category.priority)
                        ]}>
                          {priority_label(category.priority)}
                        </span>
                      </td>
                      <td>
                        <div class="flex gap-1 flex-wrap">
                          <%= for locale <- @supported_locales do %>
                            <%= if locale == "en" || get_translation(category, locale) do %>
                              <span class="badge badge-success badge-sm" title={locale_tooltip(locale, true)}>
                                {locale_flag(locale)}
                              </span>
                            <% else %>
                              <span class="badge badge-ghost badge-sm opacity-40" title={locale_tooltip(locale, false)}>
                                {locale_flag(locale)}
                              </span>
                            <% end %>
                          <% end %>
                        </div>
                      </td>
                      <td>
                        <div class="flex gap-1">
                          <.link
                            navigate={~p"/admin/categories/#{category.id}/edit"}
                            class="btn btn-ghost btn-sm"
                          >
                            <span class="hero-pencil w-4 h-4"></span>
                            Edit
                          </.link>
                          <.link navigate={~p"/#{@region_slug}/categories/#{category.slug}"} class="btn btn-ghost btn-sm">
                            View
                          </.link>
                        </div>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          </div>
        </div>

        <!-- Create Modal -->
        <%= if @creating do %>
          <div class="modal modal-open">
            <div class="modal-box max-w-md">
              <button type="button" phx-click="cancel" class="btn btn-sm btn-circle btn-ghost absolute right-4 top-4">✕</button>
              <h3 class="font-bold text-lg mb-6">Add Category</h3>
              <form phx-submit="create" class="space-y-4">
                <div class="form-control">
                  <label class="label"><span class="label-text font-medium">Name (English) <span class="text-error">*</span></span></label>
                  <input type="text" name="category[name]" class="input input-bordered w-full" required autofocus />
                </div>

                <div class="form-control">
                  <label class="label"><span class="label-text font-medium">Slug</span></label>
                  <input type="text" name="category[slug]" class="input input-bordered w-full" placeholder="Auto-generated from name" />
                </div>

                <div class="form-control">
                  <label class="label">
                    <span class="label-text font-medium">
                      Icon —
                      <a href="https://heroicons.com" target="_blank" class="link link-primary text-xs font-normal">browse heroicons.com</a>
                    </span>
                  </label>
                  <input type="text" name="category[icon]" class="input input-bordered w-full" placeholder="e.g. scale" />
                </div>

                <div class="form-control">
                  <label class="label"><span class="label-text font-medium">Priority</span></label>
                  <select name="category[priority]" class="select select-bordered w-full">
                    <option value="1">1 - Expat Essentials</option>
                    <option value="2">2 - Daily Life</option>
                    <option value="3">3 - Lifestyle</option>
                    <option value="4" selected>4 - Practical</option>
                  </select>
                </div>

                <div class="modal-action">
                  <button type="button" phx-click="cancel" class="btn btn-ghost">Cancel</button>
                  <button type="submit" class="btn btn-primary">Create & Edit</button>
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

  defp priority_class(1), do: "badge-error"
  defp priority_class(2), do: "badge-warning"
  defp priority_class(3), do: "badge-info"
  defp priority_class(_), do: "badge-ghost"

  defp priority_label(1), do: "Essential"
  defp priority_label(2), do: "Daily Life"
  defp priority_label(3), do: "Lifestyle"
  defp priority_label(_), do: "Practical"

  defp locale_tooltip("en", _), do: "English (base)"
  defp locale_tooltip("es", true), do: "Spanish translation"
  defp locale_tooltip("es", false), do: "Spanish - not translated"
  defp locale_tooltip("nl", true), do: "Dutch translation"
  defp locale_tooltip("nl", false), do: "Dutch - not translated"
  defp locale_tooltip(code, _), do: code
end
