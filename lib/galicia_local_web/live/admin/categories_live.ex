defmodule GaliciaLocalWeb.Admin.CategoriesLive do
  @moduledoc """
  Admin interface for managing categories.
  """
  use GaliciaLocalWeb, :live_view

  alias GaliciaLocal.Directory.Category

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Manage Categories")
     |> assign(:categories, load_categories())
     |> assign(:editing, nil)
     |> assign(:creating, false)}
  end

  defp load_categories do
    Category.list!()
    |> Ash.load!([:business_count])
    |> Enum.sort_by(& &1.priority)
  end

  @impl true
  def handle_event("new", _params, socket) do
    {:noreply, assign(socket, :creating, true)}
  end

  @impl true
  def handle_event("edit", %{"id" => id}, socket) do
    category = Enum.find(socket.assigns.categories, &(&1.id == id))
    {:noreply, assign(socket, :editing, category)}
  end

  @impl true
  def handle_event("cancel", _params, socket) do
    {:noreply, socket |> assign(:editing, nil) |> assign(:creating, false)}
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

    params = parse_search_queries(params)

    case Category.create(params) do
      {:ok, _category} ->
        {:noreply,
         socket
         |> assign(:categories, load_categories())
         |> assign(:creating, false)
         |> put_flash(:info, "Category created successfully")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create category")}
    end
  end

  @impl true
  def handle_event("save", %{"category" => params}, socket) do
    category = socket.assigns.editing
    params = parse_search_queries(params)

    case Ash.update(category, params) do
      {:ok, _updated} ->
        {:noreply,
         socket
         |> assign(:categories, load_categories())
         |> assign(:editing, nil)
         |> put_flash(:info, "Category updated successfully")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update category")}
    end
  end

  defp parse_search_queries(params) do
    case params["search_queries"] do
      nil -> params
      "" -> Map.put(params, "search_queries", [])
      text ->
        queries =
          text
          |> String.split("\n")
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        Map.put(params, "search_queries", queries)
    end
  end

  defp format_search_queries(nil), do: ""
  defp format_search_queries(queries) when is_list(queries), do: Enum.join(queries, "\n")

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
                    <th>Spanish</th>
                    <th>Businesses</th>
                    <th>Priority</th>
                    <th>Search Config</th>
                    <th></th>
                  </tr>
                </thead>
                <tbody>
                  <%= for category <- @categories do %>
                    <tr>
                      <td>
                        <span class={"hero-#{category.icon} w-6 h-6 inline-block text-primary"}></span>
                      </td>
                      <td class="font-medium">{category.name}</td>
                      <td class="text-base-content/70">{category.name_es}</td>
                      <td>
                        <span class="badge badge-primary">{category.business_count}</span>
                      </td>
                      <td>{category.priority}</td>
                      <td>
                        <%= if category.search_queries != nil and category.search_queries != [] do %>
                          <span class="badge badge-success badge-sm">{length(category.search_queries)} queries</span>
                        <% else %>
                          <span class="badge badge-ghost badge-sm">default</span>
                        <% end %>
                        <%= if category.enrichment_hints not in [nil, ""] do %>
                          <span class="badge badge-info badge-sm ml-1">AI hints</span>
                        <% end %>
                      </td>
                      <td>
                        <div class="flex gap-1">
                          <button
                            type="button"
                            phx-click="edit"
                            phx-value-id={category.id}
                            class="btn btn-ghost btn-sm"
                          >
                            <span class="hero-pencil w-4 h-4"></span>
                            Edit
                          </button>
                          <.link navigate={~p"/categories/#{category.slug}"} class="btn btn-ghost btn-sm">
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
            <div class="modal-box max-w-2xl max-h-[90vh]">
              <button type="button" phx-click="cancel" class="btn btn-sm btn-circle btn-ghost absolute right-4 top-4">✕</button>
              <h3 class="font-bold text-lg mb-6">Add Category</h3>
              <form phx-submit="create" class="space-y-4">
                <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <div class="form-control">
                    <label class="label"><span class="label-text font-medium">Name (English) <span class="text-error">*</span></span></label>
                    <input type="text" name="category[name]" class="input input-bordered w-full" required />
                  </div>
                  <div class="form-control">
                    <label class="label"><span class="label-text font-medium">Name (Spanish)</span></label>
                    <input type="text" name="category[name_es]" class="input input-bordered w-full" />
                  </div>
                </div>

                <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
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
                    <input type="text" name="category[icon]" class="input input-bordered w-full" placeholder="e.g. musical-note" />
                  </div>
                </div>

                <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <div class="form-control">
                    <label class="label"><span class="label-text font-medium">Priority</span></label>
                    <input type="number" name="category[priority]" value="4" class="input input-bordered w-24" />
                    <label class="label"><span class="label-text-alt text-base-content/50">Lower = higher priority</span></label>
                  </div>
                </div>

                <div class="form-control">
                  <label class="label"><span class="label-text font-medium">Description</span></label>
                  <textarea name="category[description]" class="textarea textarea-bordered w-full" rows="2"></textarea>
                </div>

                <div class="collapse collapse-arrow bg-base-200 rounded-lg">
                  <input type="checkbox" />
                  <div class="collapse-title font-medium text-sm">
                    Search & AI Configuration
                  </div>
                  <div class="collapse-content space-y-4">
                    <div class="form-control">
                      <label class="label"><span class="label-text font-medium">Search Translation</span></label>
                      <input type="text" name="category[search_translation]" class="input input-bordered w-full input-sm" placeholder="e.g. abogados" />
                      <label class="label py-1"><span class="label-text-alt text-base-content/50">Base Spanish term for Google Places</span></label>
                    </div>

                    <div class="form-control">
                      <label class="label"><span class="label-text font-medium">Search Queries</span></label>
                      <textarea
                        name="category[search_queries]"
                        class="textarea textarea-bordered w-full font-mono text-sm textarea-sm"
                        rows="4"
                        placeholder={"restaurantes\ntapas\nmarisquería"}
                      ></textarea>
                      <label class="label py-1"><span class="label-text-alt text-base-content/50">One per line. Each searched separately with city name appended.</span></label>
                    </div>

                    <div class="form-control">
                      <label class="label"><span class="label-text font-medium">AI Enrichment Hints</span></label>
                      <textarea
                        name="category[enrichment_hints]"
                        class="textarea textarea-bordered w-full textarea-sm"
                        rows="3"
                        placeholder="Extra instructions for the AI when analyzing businesses in this category..."
                      ></textarea>
                      <label class="label py-1"><span class="label-text-alt text-base-content/50">Guides AI analysis. Leave empty for default.</span></label>
                    </div>
                  </div>
                </div>

                <div class="modal-action">
                  <button type="button" phx-click="cancel" class="btn btn-ghost">Cancel</button>
                  <button type="submit" class="btn btn-primary">Create Category</button>
                </div>
              </form>
            </div>
            <div class="modal-backdrop" phx-click="cancel"></div>
          </div>
        <% end %>

        <!-- Edit Modal -->
        <%= if @editing do %>
          <div class="modal modal-open">
            <div class="modal-box max-w-2xl max-h-[90vh]">
              <button type="button" phx-click="cancel" class="btn btn-sm btn-circle btn-ghost absolute right-4 top-4">✕</button>
              <h3 class="font-bold text-lg mb-6">Edit {@editing.name}</h3>
              <form phx-submit="save" class="space-y-4">
                <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <div class="form-control">
                    <label class="label"><span class="label-text font-medium">Name (English)</span></label>
                    <input type="text" name="category[name]" value={@editing.name} class="input input-bordered w-full" />
                  </div>
                  <div class="form-control">
                    <label class="label"><span class="label-text font-medium">Name (Spanish)</span></label>
                    <input type="text" name="category[name_es]" value={@editing.name_es} class="input input-bordered w-full" />
                  </div>
                </div>

                <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <div class="form-control">
                    <label class="label">
                      <span class="label-text font-medium">
                        Icon —
                        <a href="https://heroicons.com" target="_blank" class="link link-primary text-xs font-normal">browse heroicons.com</a>
                      </span>
                    </label>
                    <div class="flex items-center gap-3">
                      <input type="text" name="category[icon]" value={@editing.icon} class="input input-bordered flex-1" />
                      <span class={"hero-#{@editing.icon} w-6 h-6 inline-block text-primary"}></span>
                    </div>
                  </div>
                  <div class="form-control">
                    <label class="label"><span class="label-text font-medium">Priority</span></label>
                    <input type="number" name="category[priority]" value={@editing.priority} class="input input-bordered w-24" />
                    <label class="label"><span class="label-text-alt text-base-content/50">Lower = higher priority</span></label>
                  </div>
                </div>

                <div class="form-control">
                  <label class="label"><span class="label-text font-medium">Description</span></label>
                  <textarea name="category[description]" class="textarea textarea-bordered w-full" rows="2">{@editing.description}</textarea>
                </div>

                <div class="collapse collapse-arrow bg-base-200 rounded-lg">
                  <input type="checkbox" checked="checked" />
                  <div class="collapse-title font-medium text-sm">
                    Search & AI Configuration
                  </div>
                  <div class="collapse-content space-y-4">
                    <div class="form-control">
                      <label class="label"><span class="label-text font-medium">Search Translation</span></label>
                      <input
                        type="text"
                        name="category[search_translation]"
                        value={@editing.search_translation}
                        class="input input-bordered w-full input-sm"
                        placeholder="e.g. abogados"
                      />
                      <label class="label py-1"><span class="label-text-alt text-base-content/50">Base Spanish term for Google Places</span></label>
                    </div>

                    <div class="form-control">
                      <label class="label"><span class="label-text font-medium">Search Queries</span></label>
                      <textarea
                        name="category[search_queries]"
                        class="textarea textarea-bordered w-full font-mono text-sm textarea-sm"
                        rows="4"
                        placeholder={"restaurantes\ntapas\nmarisquería"}
                      >{format_search_queries(@editing.search_queries)}</textarea>
                      <label class="label py-1"><span class="label-text-alt text-base-content/50">One per line. Each searched separately with city name appended.</span></label>
                    </div>

                    <div class="form-control">
                      <label class="label"><span class="label-text font-medium">AI Enrichment Hints</span></label>
                      <textarea
                        name="category[enrichment_hints]"
                        class="textarea textarea-bordered w-full textarea-sm"
                        rows="3"
                        placeholder="Extra instructions for the AI when analyzing businesses in this category..."
                      >{@editing.enrichment_hints}</textarea>
                      <label class="label py-1"><span class="label-text-alt text-base-content/50">Guides AI analysis. Leave empty for default.</span></label>
                    </div>
                  </div>
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
end
