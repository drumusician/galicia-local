defmodule GaliciaLocalWeb.Admin.CitiesLive do
  @moduledoc """
  Admin interface for managing cities.
  """
  use GaliciaLocalWeb, :live_view

  alias GaliciaLocal.Directory.City
  alias GaliciaLocal.Scraper.GooglePlaces
  alias GaliciaLocal.AI.Claude
  alias GaliciaLocalWeb.Layouts

  @impl true
  def mount(_params, _session, socket) do
    region = socket.assigns[:current_region]
    region_slug = if region, do: region.slug, else: "galicia"

    {:ok,
     socket
     |> assign(:page_title, "Manage Cities")
     |> assign(:region_slug, region_slug)
     |> assign(:editing, nil)
     |> assign(:creating, false)
     |> assign(:filter_province, "all")
     |> assign(:lookup_results, [])
     |> assign(:loading, false)
     |> assign(:form_data, %{})
     |> assign(:inline_error, nil)
     |> reload_cities()}
  end

  defp reload_cities(socket) do
    region = socket.assigns[:current_region]

    cities =
      City
      |> then(fn q -> if region, do: Ash.Query.set_tenant(q, region.id), else: q end)
      |> Ash.read!()
      |> Ash.load!([:business_count])
      |> Enum.sort_by(&{&1.province, &1.name})

    # Extract unique provinces from cities
    provinces =
      cities
      |> Enum.map(& &1.province)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort()

    socket
    |> assign(:cities, cities)
    |> assign(:provinces, provinces)
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
    {:noreply,
     socket
     |> assign(:creating, true)
     |> assign(:form_data, %{})
     |> assign(:lookup_results, [])}
  end

  @impl true
  def handle_event("edit", %{"id" => id}, socket) do
    city = Enum.find(socket.assigns.cities, &(&1.id == id))
    {:noreply,
     socket
     |> assign(:editing, city)
     |> assign(:form_data, city_to_form_data(city))
     |> assign(:lookup_results, [])}
  end

  @impl true
  def handle_event("enrich", %{"id" => id}, socket) do
    city = Enum.find(socket.assigns.cities, &(&1.id == id))

    socket =
      socket
      |> assign(:editing, city)
      |> assign(:form_data, city_to_form_data(city))
      |> assign(:loading, true)

    # Run lookup + descriptions in background
    pid = self()
    region = socket.assigns[:current_region]
    region_opts = if region do
      [region_name: region.name, country: region_country(region)]
    else
      []
    end

    Task.start(fn ->
      lookup = GooglePlaces.lookup_city(city.name, region_opts)
      descriptions = Claude.generate_city_descriptions(city.name, city.province, region_opts)
      send(pid, {:enrich_result, lookup, descriptions})
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing, nil)
     |> assign(:creating, false)
     |> assign(:lookup_results, [])
     |> assign(:form_data, %{})
     |> assign(:loading, false)
     |> assign(:inline_error, nil)}
  end

  @impl true
  def handle_event("lookup_city", %{"name" => name}, socket) when byte_size(name) > 2 do
    socket = assign(socket, :loading, true)

    pid = self()
    region = socket.assigns[:current_region]
    region_opts = if region do
      [region_name: region.name, country: region_country(region)]
    else
      []
    end

    Task.start(fn ->
      result = GooglePlaces.lookup_city(name, region_opts)
      send(pid, {:lookup_result, result})
    end)

    {:noreply, socket}
  end

  def handle_event("lookup_city", _params, socket) do
    {:noreply, assign(socket, :lookup_results, [])}
  end

  @impl true
  def handle_event("apply_lookup", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)
    result = Enum.at(socket.assigns.lookup_results, index)

    if result do
      form_data = socket.assigns.form_data
      province = detect_province(result.address)
      name = result.name || form_data["name"] || ""
      slug = name |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-") |> String.trim("-")

      # Check if city already exists by slug
      existing = Enum.find(socket.assigns.cities, &(&1.slug == slug))

      if existing && socket.assigns.creating do
        # Switch to editing the existing city, merging lookup data
        existing_data = city_to_form_data(existing)
        updated =
          existing_data
          |> Map.put("latitude", to_string(result.latitude))
          |> Map.put("longitude", to_string(result.longitude))
          |> then(fn fd -> if result.image_url, do: Map.put(fd, "image_url", result.image_url), else: fd end)

        {:noreply,
         socket
         |> assign(:creating, false)
         |> assign(:editing, existing)
         |> assign(:form_data, updated)
         |> assign(:lookup_results, [])
         |> put_flash(:info, "#{existing.name} already exists — switched to edit mode")}
      else
        updated =
          form_data
          |> Map.put("name", name)
          |> Map.put("slug", slug)
          |> Map.put("latitude", to_string(result.latitude))
          |> Map.put("longitude", to_string(result.longitude))
          |> Map.put("image_url", result.image_url || form_data["image_url"] || "")
          |> then(fn fd -> if province, do: Map.put(fd, "province", province), else: fd end)

        {:noreply,
         socket
         |> assign(:form_data, updated)
         |> assign(:lookup_results, [])}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("generate_descriptions", _params, socket) do
    name = socket.assigns.form_data["name"] || ""
    province = socket.assigns.form_data["province"] || ""

    if name != "" and province != "" do
      socket = assign(socket, :loading, true)
      pid = self()

      Task.start(fn ->
        result = Claude.generate_city_descriptions(name, province)
        send(pid, {:descriptions_result, result})
      end)

      {:noreply, socket}
    else
      {:noreply, assign(socket, :inline_error, "Name and province required for description generation")}
    end
  end

  @impl true
  def handle_event("update_form", %{"city" => params}, socket) do
    form_data = Map.merge(socket.assigns.form_data, params)
    {:noreply, assign(socket, :form_data, form_data)}
  end

  @impl true
  def handle_event("create", %{"city" => params}, socket) do
    region = socket.assigns[:current_region]
    params = process_params(params)

    # Set region_id from current region
    params =
      if region do
        Map.put(params, "region_id", region.id)
      else
        params
      end

    case City.create(params) do
      {:ok, city} ->
        {:noreply,
         socket
         |> reload_cities()
         |> assign(:creating, false)
         |> assign(:form_data, %{})
         |> put_flash(:info, "#{city.name} added successfully")}

      {:error, error} ->
        message = format_ash_error(error)
        {:noreply, put_flash(socket, :error, message)}
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
         |> assign(:form_data, %{})
         |> put_flash(:info, "#{updated.name} updated successfully")}

      {:error, error} ->
        message = format_ash_error(error)
        {:noreply, put_flash(socket, :error, message)}
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

  @impl true
  def handle_info({:lookup_result, {:ok, results}}, socket) do
    {:noreply,
     socket
     |> assign(:lookup_results, results)
     |> assign(:loading, false)
     |> assign(:inline_error, nil)}
  end

  def handle_info({:lookup_result, {:error, _}}, socket) do
    {:noreply,
     socket
     |> assign(:loading, false)
     |> assign(:inline_error, "City lookup failed")}
  end

  def handle_info({:descriptions_result, {:ok, %{description: desc, description_es: desc_es} = result}}, socket) do
    form_data =
      socket.assigns.form_data
      |> Map.put("description", desc)
      |> Map.put("description_es", desc_es)
      |> then(fn fd -> if result[:population], do: Map.put(fd, "population", to_string(result[:population])), else: fd end)

    {:noreply,
     socket
     |> assign(:form_data, form_data)
     |> assign(:loading, false)
     |> assign(:inline_error, nil)}
  end

  def handle_info({:descriptions_result, {:error, _}}, socket) do
    {:noreply,
     socket
     |> assign(:loading, false)
     |> assign(:inline_error, "Failed to generate descriptions")}
  end

  def handle_info({:enrich_result, lookup, descriptions}, socket) do
    form_data = socket.assigns.form_data

    # Apply lookup data
    form_data =
      case lookup do
        {:ok, [first | _]} ->
          form_data
          |> Map.put("latitude", to_string(first.latitude))
          |> Map.put("longitude", to_string(first.longitude))
          |> then(fn fd ->
            if first.image_url, do: Map.put(fd, "image_url", first.image_url), else: fd
          end)

        _ ->
          form_data
      end

    # Apply descriptions
    form_data =
      case descriptions do
        {:ok, %{description: desc, description_es: desc_es} = result} ->
          form_data
          |> Map.put("description", desc)
          |> Map.put("description_es", desc_es)
          |> then(fn fd -> if result[:population], do: Map.put(fd, "population", to_string(result[:population])), else: fd end)

        _ ->
          form_data
      end

    {:noreply,
     socket
     |> assign(:form_data, form_data)
     |> assign(:loading, false)}
  end

  defp city_to_form_data(city) do
    %{
      "name" => city.name || "",
      "slug" => city.slug || "",
      "province" => city.province || "",
      "population" => if(city.population, do: to_string(city.population), else: ""),
      "latitude" => if(city.latitude, do: to_string(city.latitude), else: ""),
      "longitude" => if(city.longitude, do: to_string(city.longitude), else: ""),
      "image_url" => city.image_url || "",
      "description" => city.description || "",
      "description_es" => city.description_es || "",
      "featured" => city.featured
    }
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

  defp format_ash_error(%Ash.Error.Invalid{errors: errors}) do
    errors
    |> Enum.map(fn
      %{field: field, message: message} -> "#{field} #{message}"
      other -> inspect(other)
    end)
    |> Enum.join(", ")
  end

  defp format_ash_error(error), do: "Failed: #{inspect(error)}"

  # Convert region country_code to country name
  defp region_country(%{country_code: "ES"}), do: "Spain"
  defp region_country(%{country_code: "NL"}), do: "Netherlands"
  defp region_country(%{country_code: code}), do: code
  defp region_country(_), do: "Spain"

  defp detect_province(nil), do: nil
  defp detect_province(address) do
    cond do
      # Spanish/Galician provinces
      String.contains?(address, "A Coruña") or String.contains?(address, "La Coruña") -> "A Coruña"
      String.contains?(address, "Lugo") -> "Lugo"
      String.contains?(address, "Ourense") or String.contains?(address, "Orense") -> "Ourense"
      String.contains?(address, "Pontevedra") -> "Pontevedra"
      # Dutch provinces
      String.contains?(address, "Noord-Holland") -> "Noord-Holland"
      String.contains?(address, "Zuid-Holland") -> "Zuid-Holland"
      String.contains?(address, "Utrecht") -> "Utrecht"
      String.contains?(address, "Noord-Brabant") -> "Noord-Brabant"
      String.contains?(address, "Gelderland") -> "Gelderland"
      String.contains?(address, "Overijssel") -> "Overijssel"
      String.contains?(address, "Limburg") -> "Limburg"
      String.contains?(address, "Groningen") -> "Groningen"
      String.contains?(address, "Flevoland") -> "Flevoland"
      String.contains?(address, "Friesland") or String.contains?(address, "Fryslân") -> "Friesland"
      String.contains?(address, "Drenthe") -> "Drenthe"
      String.contains?(address, "Zeeland") -> "Zeeland"
      true -> nil
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
                  <button type="button" phx-click="enrich" phx-value-id={city.id} class="btn btn-sm btn-ghost text-info">
                    <span class="hero-sparkles w-4 h-4"></span>
                    Enrich
                  </button>
                  <button type="button" phx-click="edit" phx-value-id={city.id} class="btn btn-sm btn-ghost">
                    <span class="hero-pencil w-4 h-4"></span>
                    Edit
                  </button>
                  <.link navigate={~p"/#{@region_slug}/cities/#{city.slug}"} class="btn btn-sm btn-ghost">
                    View
                  </.link>
                </div>
              </div>
            </div>
          <% end %>
        </div>

        <!-- Create Modal -->
        <%= if @creating do %>
          <.city_modal
            title="Add New City"
            action="create"
            city={nil}
            provinces={@provinces}
            form_data={@form_data}
            lookup_results={@lookup_results}
            loading={@loading}
            inline_error={@inline_error}
          />
        <% end %>

        <!-- Edit Modal -->
        <%= if @editing do %>
          <.city_modal
            title={"Edit #{@editing.name}"}
            action="save"
            city={@editing}
            provinces={@provinces}
            form_data={@form_data}
            lookup_results={@lookup_results}
            loading={@loading}
            inline_error={@inline_error}
          />
        <% end %>
      </main>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :action, :string, required: true
  attr :city, :map, default: nil
  attr :provinces, :list, required: true
  attr :form_data, :map, required: true
  attr :lookup_results, :list, default: []
  attr :loading, :boolean, default: false
  attr :inline_error, :string, default: nil

  defp city_modal(assigns) do
    ~H"""
    <div class="modal modal-open">
      <div class="modal-box max-w-2xl">
        <div class="flex items-center justify-between mb-4">
          <h3 class="font-bold text-xl">{@title}</h3>
          <%= if @loading do %>
            <span class="loading loading-spinner loading-sm text-primary"></span>
          <% end %>
        </div>

        <%= if @inline_error do %>
          <div class="alert alert-error alert-sm py-2 text-sm">
            <span class="hero-exclamation-circle w-4 h-4"></span>
            {@inline_error}
          </div>
        <% end %>

        <form phx-submit={@action} phx-change="update_form" class="space-y-5">
          <!-- Name + Lookup -->
          <div>
            <label class="block text-sm font-medium mb-1.5">Name *</label>
            <div class="join w-full">
              <input
                type="text"
                name="city[name]"
                value={@form_data["name"] || (@city && @city.name)}
                required
                class="input input-bordered join-item w-full"
                placeholder="e.g., Cambados"
              />
              <button
                type="button"
                phx-click="lookup_city"
                phx-value-name={@form_data["name"] || (@city && @city.name) || ""}
                class="btn btn-outline join-item"
                disabled={@loading}
              >
                <span class="hero-magnifying-glass w-4 h-4"></span>
                Lookup
              </button>
            </div>
          </div>

          <!-- Lookup Results -->
          <%= if @lookup_results != [] do %>
            <div class="space-y-2">
              <p class="text-xs font-semibold text-info uppercase tracking-wider">Places API Results</p>
              <%= for {result, index} <- Enum.with_index(@lookup_results) do %>
                <div class="flex items-center justify-between bg-info/10 rounded-lg px-4 py-2.5">
                  <div class="min-w-0">
                    <p class="font-medium text-sm">{result.name}</p>
                    <p class="text-xs text-base-content/60 truncate">{result.address}</p>
                    <p class="text-xs text-base-content/40">{result.latitude}, {result.longitude}</p>
                  </div>
                  <button
                    type="button"
                    phx-click="apply_lookup"
                    phx-value-index={index}
                    class="btn btn-xs btn-info btn-outline ml-3 shrink-0"
                  >
                    Apply
                  </button>
                </div>
              <% end %>
            </div>
          <% end %>

          <!-- Slug + Province -->
          <div class="grid grid-cols-2 gap-4">
            <div>
              <label class="block text-sm font-medium mb-1.5">Slug *</label>
              <input
                type="text"
                name="city[slug]"
                value={@form_data["slug"] || (@city && @city.slug)}
                required
                class="input input-bordered w-full"
                placeholder="e.g., cambados"
              />
            </div>
            <div>
              <label class="block text-sm font-medium mb-1.5">Province *</label>
              <select name="city[province]" required class="select select-bordered w-full">
                <option value="">Select...</option>
                <%= for province <- @provinces do %>
                  <option
                    value={province}
                    selected={(@form_data["province"] || (@city && @city.province)) == province}
                  >
                    {province}
                  </option>
                <% end %>
              </select>
            </div>
          </div>

          <div class="divider text-xs text-base-content/40 my-1">LOCATION</div>

          <!-- Coordinates + Population -->
          <div class="grid grid-cols-3 gap-4">
            <div>
              <label class="block text-sm font-medium mb-1.5">Latitude</label>
              <input
                type="text"
                name="city[latitude]"
                value={@form_data["latitude"] || (@city && @city.latitude)}
                class="input input-bordered input-sm w-full"
                placeholder="42.5138"
              />
            </div>
            <div>
              <label class="block text-sm font-medium mb-1.5">Longitude</label>
              <input
                type="text"
                name="city[longitude]"
                value={@form_data["longitude"] || (@city && @city.longitude)}
                class="input input-bordered input-sm w-full"
                placeholder="-8.8147"
              />
            </div>
            <div>
              <label class="block text-sm font-medium mb-1.5">Population</label>
              <input
                type="number"
                name="city[population]"
                value={@form_data["population"] || (@city && @city.population)}
                class="input input-bordered input-sm w-full"
                placeholder="13000"
              />
            </div>
          </div>

          <div class="divider text-xs text-base-content/40 my-1">MEDIA & OPTIONS</div>

          <!-- Image URL -->
          <div>
            <label class="block text-sm font-medium mb-1.5">Image URL</label>
            <input
              type="text"
              name="city[image_url]"
              value={@form_data["image_url"] || (@city && @city.image_url)}
              class="input input-bordered w-full"
              placeholder="https://..."
            />
            <%= if (@form_data["image_url"] || (@city && @city.image_url)) not in [nil, ""] do %>
              <div class="mt-2 rounded-lg overflow-hidden h-20 w-36">
                <img
                  src={@form_data["image_url"] || (@city && @city.image_url)}
                  class="w-full h-full object-cover"
                  alt="Preview"
                />
              </div>
            <% end %>
          </div>

          <!-- Featured -->
          <label class="flex items-center gap-3 cursor-pointer">
            <input
              type="checkbox"
              name="city[featured]"
              value="true"
              checked={if(is_nil(@form_data["featured"]), do: @city && @city.featured, else: @form_data["featured"])}
              class="checkbox checkbox-primary checkbox-sm"
            />
            <span class="text-sm">Featured on homepage</span>
          </label>

          <div class="divider text-xs text-base-content/40 my-1">DESCRIPTIONS</div>

          <!-- Descriptions -->
          <div class="space-y-3">
            <div class="flex justify-end">
              <button
                type="button"
                phx-click="generate_descriptions"
                class="btn btn-xs btn-outline btn-secondary"
                disabled={@loading}
              >
                <span class="hero-sparkles w-3 h-3"></span>
                Generate with AI
              </button>
            </div>
            <div>
              <label class="block text-sm font-medium mb-1.5">English</label>
              <textarea
                name="city[description]"
                rows="2"
                class="textarea textarea-bordered w-full text-sm"
                placeholder="A brief description of the city..."
              >{@form_data["description"] || (@city && @city.description)}</textarea>
            </div>
            <div>
              <label class="block text-sm font-medium mb-1.5">Spanish</label>
              <textarea
                name="city[description_es]"
                rows="2"
                class="textarea textarea-bordered w-full text-sm"
                placeholder="Una breve descripción de la ciudad..."
              >{@form_data["description_es"] || (@city && @city.description_es)}</textarea>
            </div>
          </div>

          <div class="modal-action">
            <button type="button" phx-click="cancel" class="btn btn-ghost btn-sm">Cancel</button>
            <button type="submit" class="btn btn-primary btn-sm">
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
