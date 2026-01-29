defmodule GaliciaLocalWeb.Admin.CategoriesLive do
  @moduledoc """
  Admin interface for managing categories.
  """
  use GaliciaLocalWeb, :live_view

  alias GaliciaLocal.Directory.Category

  @impl true
  def mount(_params, _session, socket) do
    categories = Category.list!()
                 |> Ash.load!([:business_count])
                 |> Enum.sort_by(& &1.priority)

    {:ok,
     socket
     |> assign(:page_title, "Manage Categories")
     |> assign(:categories, categories)
     |> assign(:editing, nil)}
  end

  @impl true
  def handle_event("edit", %{"id" => id}, socket) do
    category = Enum.find(socket.assigns.categories, &(&1.id == id))
    {:noreply, assign(socket, :editing, category)}
  end

  @impl true
  def handle_event("cancel", _params, socket) do
    {:noreply, assign(socket, :editing, nil)}
  end

  @impl true
  def handle_event("save", %{"category" => params}, socket) do
    category = socket.assigns.editing

    case Ash.update(category, params) do
      {:ok, _updated} ->
        categories = Category.list!()
                     |> Ash.load!([:business_count])
                     |> Enum.sort_by(& &1.priority)

        {:noreply,
         socket
         |> assign(:categories, categories)
         |> assign(:editing, nil)
         |> put_flash(:info, "Category updated successfully")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update category")}
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

        <!-- Edit Modal -->
        <%= if @editing do %>
          <div class="modal modal-open">
            <div class="modal-box">
              <h3 class="font-bold text-lg mb-4">Edit {Ash.CiString.value(@editing.name)}</h3>
              <form phx-submit="save">
                <div class="form-control mb-4">
                  <label class="label">
                    <span class="label-text">Name (English)</span>
                  </label>
                  <input
                    type="text"
                    name="category[name]"
                    value={@editing.name}
                    class="input input-bordered"
                  />
                </div>

                <div class="form-control mb-4">
                  <label class="label">
                    <span class="label-text">Name (Spanish)</span>
                  </label>
                  <input
                    type="text"
                    name="category[name_es]"
                    value={@editing.name_es}
                    class="input input-bordered"
                  />
                </div>

                <div class="form-control mb-4">
                  <label class="label">
                    <span class="label-text">Icon (Heroicon name, e.g. "scale", "heart")</span>
                  </label>
                  <div class="flex items-center gap-3">
                    <input
                      type="text"
                      name="category[icon]"
                      value={@editing.icon}
                      class="input input-bordered flex-1"
                    />
                    <span class={"hero-#{@editing.icon} w-6 h-6 inline-block text-primary"}></span>
                  </div>
                </div>

                <div class="form-control mb-4">
                  <label class="label">
                    <span class="label-text">Priority (lower = higher)</span>
                  </label>
                  <input
                    type="number"
                    name="category[priority]"
                    value={@editing.priority}
                    class="input input-bordered w-24"
                  />
                </div>

                <div class="form-control mb-4">
                  <label class="label">
                    <span class="label-text">Description</span>
                  </label>
                  <textarea
                    name="category[description]"
                    class="textarea textarea-bordered"
                    rows="3"
                  >{@editing.description}</textarea>
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
