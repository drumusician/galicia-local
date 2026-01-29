defmodule GaliciaLocalWeb.Admin.CitiesLive do
  @moduledoc """
  Admin interface for managing cities.
  """
  use GaliciaLocalWeb, :live_view

  alias GaliciaLocal.Directory.City
  alias GaliciaLocalWeb.Layouts

  @provinces ["A Coruña", "Lugo", "Ourense", "Pontevedra"]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Manage Cities")
     |> assign(:provinces, @provinces)
     |> assign(:editing, nil)
     |> assign(:creating, false)
     |> assign(:filter_province, "all")
     |> reload_cities()}
  end

  defp reload_cities(socket) do
    cities = City.list!()
             |> Ash.load!([:business_count])
             |> Enum.sort_by(&{&1.province, &1.name})

    assign(socket, :cities, cities)
  end

  defp filtered_cities(cities, "all"), do: cities
  defp filtered_cities(cities, province) do
    Enum.filter(cities, &(&1.province == province))
  end

  @impl true
  def handle_event("filter", %{"province" => province}, socket) do
    {:noreply, assign(socket, :filter_province, province)}
  end

  @impl true
  def handle_event("new", _params, socket) do
    {:noreply, assign(socket, :creating, true)}
  end

  @impl true
  def handle_event("edit", %{"id" => id}, socket) do
    city = Enum.find(socket.assigns.cities, &(&1.id == id))
    {:noreply, assign(socket, :editing, city)}
  end

  @impl true
  def handle_event("cancel", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing, nil)
     |> assign(:creating, false)}
  end

  @impl true
  def handle_event("create", %{"city" => params}, socket) do
    params = process_params(params)

    case City.create(params) do
      {:ok, city} ->
        {:noreply,
         socket
         |> reload_cities()
         |> assign(:creating, false)
         |> put_flash(:info, "#{city.name} added successfully")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Failed to create city: #{inspect(error)}")}
    end
  end

  @impl true
  def handle_event("save", %{"city" => params}, socket) do
    city = socket.assigns.editing
    params = process_params(params)

    case Ash.update(city, params) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> reload_cities()
         |> assign(:editing, nil)
         |> put_flash(:info, "#{updated.name} updated successfully")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update city")}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    case City.get_by_id(id) do
      {:ok, city} ->
        case Ash.destroy(city) do
          :ok ->
            {:noreply,
             socket
             |> reload_cities()
             |> put_flash(:info, "#{city.name} deleted")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to delete city")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "City not found")}
    end
  end

  defp process_params(params) do
    params
    |> Map.put("featured", params["featured"] == "true")
    |> maybe_parse_number("population")
    |> maybe_parse_decimal("latitude")
    |> maybe_parse_decimal("longitude")
  end

  defp maybe_parse_number(params, key) do
    case params[key] do
      nil -> params
      "" -> Map.put(params, key, nil)
      val when is_binary(val) ->
        case Integer.parse(val) do
          {num, _} -> Map.put(params, key, num)
          :error -> params
        end
      _ -> params
    end
  end

  defp maybe_parse_decimal(params, key) do
    case params[key] do
      nil -> params
      "" -> Map.put(params, key, nil)
      val when is_binary(val) ->
        case Decimal.parse(val) do
          {dec, _} -> Map.put(params, key, dec)
          :error -> params
        end
      _ -> params
    end
  end

  defp format_population(nil), do: "-"
  defp format_population(pop) when is_integer(pop) do
    pop
    |> Integer.to_string()
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.join(",")
    |> String.reverse()
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
              <h1 class="text-2xl font-bold">Manage Cities</h1>
            </div>
            <div class="flex items-center gap-2">
              <span class="text-sm text-base-content/70">{length(@cities)} cities</span>
              <button type="button" phx-click="new" class="btn btn-primary btn-sm">
                <span class="hero-plus w-4 h-4"></span>
                Add City
              </button>
            </div>
          </div>
        </div>
      </header>

      <main class="container mx-auto px-6 py-8">
        <!-- Province Filter -->
        <div class="flex gap-2 mb-6 flex-wrap">
          <button
            type="button"
            phx-click="filter"
            phx-value-province="all"
            class={["btn btn-sm", if(@filter_province == "all", do: "btn-primary", else: "btn-ghost")]}
          >
            All ({length(@cities)})
          </button>
          <%= for province <- @provinces do %>
            <button
              type="button"
              phx-click="filter"
              phx-value-province={province}
              class={["btn btn-sm", if(@filter_province == province, do: "btn-secondary", else: "btn-ghost")]}
            >
              {province} ({Enum.count(@cities, &(&1.province == province))})
            </button>
          <% end %>
        </div>

        <!-- Cities Grid -->
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          <%= for city <- filtered_cities(@cities, @filter_province) do %>
            <div class="card bg-base-100 shadow-xl">
              <%= if city.image_url do %>
                <figure class="h-32">
                  <img src={city.image_url} alt={city.name} class="w-full h-full object-cover" />
                </figure>
              <% else %>
                <figure class="h-32 bg-base-300 flex items-center justify-center">
                  <span class="hero-map-pin w-12 h-12 text-base-content/30"></span>
                </figure>
              <% end %>
              <div class="card-body">
                <h2 class="card-title">
                  {city.name}
                  <%= if city.featured do %>
                    <span class="badge badge-accent badge-sm">Featured</span>
                  <% end %>
                </h2>
                <p class="text-sm text-base-content/70">{city.province}</p>

                <div class="flex flex-wrap gap-2 mt-2">
                  <span class="badge badge-outline badge-sm">
                    {city.business_count} businesses
                  </span>
                  <%= if city.population do %>
                    <span class="badge badge-ghost badge-sm">
                      Pop: {format_population(city.population)}
                    </span>
                  <% end %>
                </div>

                <%= if city.description do %>
                  <p class="text-sm text-base-content/60 mt-2 line-clamp-2">{city.description}</p>
                <% end %>

                <div class="card-actions justify-end mt-4">
                  <button
                    type="button"
                    phx-click="delete"
                    phx-value-id={city.id}
                    data-confirm={"Delete #{city.name}? This cannot be undone."}
                    class="btn btn-ghost btn-sm text-error"
                  >
                    <span class="hero-trash w-4 h-4"></span>
                  </button>
                  <button type="button" phx-click="edit" phx-value-id={city.id} class="btn btn-sm btn-ghost">
                    <span class="hero-pencil w-4 h-4"></span>
                    Edit
                  </button>
                  <.link navigate={~p"/cities/#{city.slug}"} class="btn btn-sm btn-ghost">
                    View
                  </.link>
                </div>
              </div>
            </div>
          <% end %>
        </div>

        <!-- Create Modal -->
        <%= if @creating do %>
          <.city_modal title="Add New City" action="create" city={nil} provinces={@provinces} />
        <% end %>

        <!-- Edit Modal -->
        <%= if @editing do %>
          <.city_modal title={"Edit #{@editing.name}"} action="save" city={@editing} provinces={@provinces} />
        <% end %>
      </main>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :action, :string, required: true
  attr :city, :map, default: nil
  attr :provinces, :list, required: true

  defp city_modal(assigns) do
    ~H"""
    <div class="modal modal-open">
      <div class="modal-box max-w-2xl">
        <h3 class="font-bold text-lg mb-4">{@title}</h3>
        <form phx-submit={@action}>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <!-- Name -->
            <div class="form-control">
              <label class="label">
                <span class="label-text">Name *</span>
              </label>
              <input
                type="text"
                name="city[name]"
                value={@city && @city.name}
                required
                class="input input-bordered"
                placeholder="e.g., Cambados"
              />
            </div>

            <!-- Slug -->
            <div class="form-control">
              <label class="label">
                <span class="label-text">Slug *</span>
              </label>
              <input
                type="text"
                name="city[slug]"
                value={@city && @city.slug}
                required
                class="input input-bordered"
                placeholder="e.g., cambados"
              />
            </div>

            <!-- Province -->
            <div class="form-control">
              <label class="label">
                <span class="label-text">Province *</span>
              </label>
              <select name="city[province]" required class="select select-bordered">
                <option value="">Select province...</option>
                <%= for province <- @provinces do %>
                  <option value={province} selected={@city && @city.province == province}>
                    {province}
                  </option>
                <% end %>
              </select>
            </div>

            <!-- Population -->
            <div class="form-control">
              <label class="label">
                <span class="label-text">Population</span>
              </label>
              <input
                type="number"
                name="city[population]"
                value={@city && @city.population}
                class="input input-bordered"
                placeholder="e.g., 13000"
              />
            </div>

            <!-- Latitude -->
            <div class="form-control">
              <label class="label">
                <span class="label-text">Latitude</span>
              </label>
              <input
                type="text"
                name="city[latitude]"
                value={@city && @city.latitude}
                class="input input-bordered"
                placeholder="e.g., 42.5138"
              />
            </div>

            <!-- Longitude -->
            <div class="form-control">
              <label class="label">
                <span class="label-text">Longitude</span>
              </label>
              <input
                type="text"
                name="city[longitude]"
                value={@city && @city.longitude}
                class="input input-bordered"
                placeholder="e.g., -8.8147"
              />
            </div>
          </div>

          <!-- Image URL -->
          <div class="form-control mt-4">
            <label class="label">
              <span class="label-text">Image URL</span>
            </label>
            <input
              type="text"
              name="city[image_url]"
              value={@city && @city.image_url}
              class="input input-bordered"
              placeholder="https://..."
            />
          </div>

          <!-- Description (English) -->
          <div class="form-control mt-4">
            <label class="label">
              <span class="label-text">Description (English)</span>
            </label>
            <textarea
              name="city[description]"
              rows="2"
              class="textarea textarea-bordered"
              placeholder="A brief description of the city..."
            >{@city && @city.description}</textarea>
          </div>

          <!-- Description (Spanish) -->
          <div class="form-control mt-4">
            <label class="label">
              <span class="label-text">Description (Spanish)</span>
            </label>
            <textarea
              name="city[description_es]"
              rows="2"
              class="textarea textarea-bordered"
              placeholder="Una breve descripción de la ciudad..."
            >{@city && @city.description_es}</textarea>
          </div>

          <!-- Featured -->
          <div class="form-control mt-4">
            <label class="label cursor-pointer justify-start gap-4">
              <input
                type="checkbox"
                name="city[featured]"
                value="true"
                checked={@city && @city.featured}
                class="checkbox checkbox-primary"
              />
              <span class="label-text">Featured on homepage</span>
            </label>
          </div>

          <div class="modal-action">
            <button type="button" phx-click="cancel" class="btn btn-ghost">Cancel</button>
            <button type="submit" class="btn btn-primary">
              <%= if @city, do: "Save Changes", else: "Add City" %>
            </button>
          </div>
        </form>
      </div>
      <div class="modal-backdrop" phx-click="cancel"></div>
    </div>
    """
  end
end
