defmodule GaliciaLocalWeb.Admin.RegionsLive do
  @moduledoc """
  Admin page for managing regions.
  Features a multi-step wizard for creating new regions with Claude-powered enrichment.
  """
  use GaliciaLocalWeb, :live_view

  alias GaliciaLocal.Directory.{Region, City}
  alias GaliciaLocal.Pipeline.RegionBootstrap

  @impl true
  def mount(_params, _session, socket) do
    regions = Region.list!() |> Ash.load!(:city_count)

    {:ok,
     socket
     |> assign(:page_title, "Manage Regions")
     |> assign(:regions, regions)
     |> assign(:wizard_step, nil)
     |> assign(:wizard_name, "")
     |> assign(:wizard_data, nil)
     |> assign(:wizard_cities, [])
     |> assign(:editing, nil)
     |> assign(:form_data, %{})
     |> assign(:inline_error, nil)
     |> assign(:loading, false)
     |> assign(:settings_json, "{}")
     |> assign(:discovery_urls, [])
     |> assign(:discovery_result, nil)
     |> assign(:osm_import_result, nil)}
  end

  # --- Wizard: Step 1 - Enter name ---

  @impl true
  def handle_event("new", _params, socket) do
    {:noreply,
     socket
     |> assign(:wizard_step, :name)
     |> assign(:wizard_name, "")
     |> assign(:wizard_data, nil)
     |> assign(:wizard_cities, [])
     |> assign(:inline_error, nil)
     |> assign(:loading, false)
     |> assign(:discovery_urls, [])
     |> assign(:discovery_result, nil)
     |> assign(:osm_import_result, nil)}
  end

  def handle_event("update_wizard_name", %{"name" => name}, socket) do
    {:noreply, assign(socket, :wizard_name, name)}
  end

  def handle_event("generate_region", _params, socket) do
    name = String.trim(socket.assigns.wizard_name)

    if name == "" do
      {:noreply, assign(socket, :inline_error, "Please enter a region name")}
    else
      socket = assign(socket, loading: true, inline_error: nil)
      send(self(), {:enrich_region, name})
      {:noreply, socket}
    end
  end

  def handle_event("skip_generate", _params, socket) do
    {:noreply,
     socket
     |> assign(:wizard_step, :review_region)
     |> assign(:form_data, %{
       "name" => socket.assigns.wizard_name,
       "slug" => slugify(socket.assigns.wizard_name),
       "country_code" => "",
       "default_locale" => "en",
       "supported_locales" => "en",
       "timezone" => "UTC",
       "active" => true,
       "tagline" => "",
       "hero_image_url" => ""
     })
     |> assign(:settings_json, "{\n  \"phrases\": [],\n  \"cultural_tips\": [],\n  \"enrichment_context\": {}\n}")
     |> assign(:loading, false)}
  end

  # --- Wizard: Step 2 - Review region ---

  def handle_event("update_form", %{"region" => params}, socket) do
    settings_json = params["settings_json"] || socket.assigns.settings_json

    form_data =
      socket.assigns.form_data
      |> Map.merge(Map.drop(params, ["settings_json"]))
      |> Map.put("active", params["active"] == "true")

    {:noreply,
     socket
     |> assign(:form_data, form_data)
     |> assign(:settings_json, settings_json)}
  end

  def handle_event("save_region_and_suggest_cities", %{"region" => params}, socket) do
    case save_region(socket, params) do
      {:ok, region} ->
        socket =
          socket
          |> assign(:regions, Region.list!() |> Ash.load!(:city_count))
          |> assign(:wizard_step, :suggest_cities)
          |> assign(:wizard_data, region)
          |> assign(:loading, true)
          |> assign(:inline_error, nil)

        send(self(), {:suggest_cities, region.name, region.country_code})
        {:noreply, socket}

      {:error, message} ->
        {:noreply, assign(socket, :inline_error, message)}
    end
  end

  def handle_event("save_region_only", _params, socket) do
    case save_region(socket, socket.assigns.form_data) do
      {:ok, _region} ->
        {:noreply,
         socket
         |> assign(:regions, Region.list!() |> Ash.load!(:city_count))
         |> assign(:wizard_step, nil)
         |> put_flash(:info, "Region saved successfully")}

      {:error, message} ->
        {:noreply, assign(socket, :inline_error, message)}
    end
  end

  # --- Wizard: Step 3 - Review cities ---

  def handle_event("toggle_city", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)
    cities = socket.assigns.wizard_cities

    cities =
      List.update_at(cities, index, fn city ->
        Map.put(city, "selected", !Map.get(city, "selected", true))
      end)

    {:noreply, assign(socket, :wizard_cities, cities)}
  end

  def handle_event("create_cities", _params, socket) do
    region = socket.assigns.wizard_data
    selected_cities = Enum.filter(socket.assigns.wizard_cities, &Map.get(&1, "selected", true))

    if selected_cities == [] do
      {:noreply, assign(socket, :inline_error, "Select at least one city")}
    else
      socket = assign(socket, loading: true, inline_error: nil)

      results =
        Enum.map(selected_cities, fn city_data ->
          City.create(%{
            name: city_data["name"],
            slug: city_data["slug"],
            province: city_data["province"] || "Unknown",
            latitude: city_data["latitude"] && Decimal.new("#{city_data["latitude"]}"),
            longitude: city_data["longitude"] && Decimal.new("#{city_data["longitude"]}"),
            population: city_data["population"],
            featured: city_data["featured"] || false,
            region_id: region.id
          })
        end)

      created = Enum.count(results, &match?({:ok, _}, &1))
      failed = Enum.count(results, &match?({:error, _}, &1))

      if failed > 0 do
        errors =
          results
          |> Enum.filter(&match?({:error, _}, &1))
          |> Enum.map(fn {:error, e} -> inspect(e) end)
          |> Enum.take(3)
          |> Enum.join("; ")

        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:inline_error, "#{created} created, #{failed} failed: #{errors}")}
      else
        {:noreply,
         socket
         |> assign(:wizard_step, :discover)
         |> assign(:loading, false)
         |> assign(:regions, Region.list!() |> Ash.load!(:city_count))
         |> put_flash(:info, "#{created} cities created")}
      end
    end
  end

  def handle_event("skip_cities", _params, socket) do
    {:noreply,
     socket
     |> assign(:wizard_step, nil)
     |> put_flash(:info, "Region created. You can add cities later.")}
  end

  # --- Wizard: Step 4 - Discover ---

  def handle_event("suggest_urls", _params, socket) do
    region = socket.assigns.wizard_data
    socket = assign(socket, loading: true, inline_error: nil)
    send(self(), {:suggest_discovery_urls, region.id})
    {:noreply, socket}
  end

  def handle_event("suggest_urls_tavily", _params, socket) do
    region = socket.assigns.wizard_data
    socket = assign(socket, loading: true, inline_error: nil)
    send(self(), {:suggest_discovery_urls_tavily, region.id})
    {:noreply, socket}
  end

  def handle_event("start_osm_import", _params, socket) do
    region = socket.assigns.wizard_data
    socket = assign(socket, loading: true, inline_error: nil)
    send(self(), {:start_osm_import, region.id})
    {:noreply, socket}
  end

  def handle_event("toggle_url", %{"city" => city_idx_str, "url" => url_idx_str}, socket) do
    city_idx = String.to_integer(city_idx_str)
    url_idx = String.to_integer(url_idx_str)

    discovery_urls =
      List.update_at(socket.assigns.discovery_urls, city_idx, fn city_group ->
        urls =
          List.update_at(city_group.urls, url_idx, fn url ->
            Map.put(url, "selected", !Map.get(url, "selected", true))
          end)

        Map.put(city_group, :urls, urls)
      end)

    {:noreply, assign(socket, :discovery_urls, discovery_urls)}
  end

  def handle_event("start_crawling", _params, socket) do
    region = socket.assigns.wizard_data

    url_groups =
      socket.assigns.discovery_urls
      |> Enum.map(fn group ->
        selected_urls =
          group.urls
          |> Enum.filter(&Map.get(&1, "selected", true))
          |> Enum.map(& &1["url"])

        %{city_id: group.city_id, urls: selected_urls}
      end)
      |> Enum.filter(fn g -> g.urls != [] end)

    if url_groups == [] do
      {:noreply, assign(socket, :inline_error, "Select at least one URL to crawl")}
    else
      socket = assign(socket, loading: true, inline_error: nil)
      send(self(), {:start_crawling, url_groups, region.id})
      {:noreply, socket}
    end
  end

  def handle_event("skip_discovery", _params, socket) do
    {:noreply,
     socket
     |> assign(:wizard_step, nil)
     |> put_flash(:info, "Region ready! You can start discovery later.")}
  end

  def handle_event("finish", _params, socket) do
    {:noreply, assign(socket, :wizard_step, nil)}
  end

  # --- Discover (for existing regions) ---

  def handle_event("discover", %{"id" => id}, socket) do
    region = Region.get_by_id!(id)

    {:noreply,
     socket
     |> assign(:wizard_step, :discover)
     |> assign(:wizard_data, region)
     |> assign(:discovery_urls, [])
     |> assign(:discovery_result, nil)
     |> assign(:osm_import_result, nil)
     |> assign(:inline_error, nil)
     |> assign(:loading, false)}
  end

  # --- Edit existing region (modal) ---

  def handle_event("edit", %{"id" => id}, socket) do
    case Region.get_by_id(id) do
      {:ok, region} ->
        settings_json =
          case Jason.encode(region.settings || %{}, pretty: true) do
            {:ok, json} -> json
            _ -> "{}"
          end

        {:noreply,
         socket
         |> assign(:editing, region)
         |> assign(:form_data, %{
           "name" => region.name,
           "slug" => region.slug,
           "country_code" => region.country_code,
           "default_locale" => region.default_locale,
           "supported_locales" => Enum.join(region.supported_locales || [], ", "),
           "timezone" => region.timezone,
           "active" => region.active,
           "tagline" => region.tagline || "",
           "hero_image_url" => region.hero_image_url || ""
         })
         |> assign(:settings_json, settings_json)
         |> assign(:inline_error, nil)}

      _ ->
        {:noreply, put_flash(socket, :error, "Region not found")}
    end
  end

  def handle_event("cancel", _params, socket) do
    {:noreply, assign(socket, editing: nil, wizard_step: nil)}
  end

  def handle_event("save", %{"region" => params}, socket) do
    case save_existing_region(socket, params) do
      {:ok, _region} ->
        {:noreply,
         socket
         |> assign(:regions, Region.list!() |> Ash.load!(:city_count))
         |> assign(:editing, nil)
         |> put_flash(:info, "Region saved successfully")}

      {:error, message} ->
        {:noreply, assign(socket, :inline_error, message)}
    end
  end

  # --- Async handlers ---

  @impl true
  def handle_info({:enrich_region, name}, socket) do
    case RegionBootstrap.enrich_region(name) do
      {:ok, data} ->
        settings = data["settings"] || %{}
        settings_json = Jason.encode!(settings, pretty: true)

        {:noreply,
         socket
         |> assign(:wizard_step, :review_region)
         |> assign(:wizard_data, data)
         |> assign(:form_data, %{
           "name" => data["name"] || name,
           "slug" => data["slug"] || slugify(name),
           "country_code" => data["country_code"] || "",
           "default_locale" => data["default_locale"] || "en",
           "supported_locales" => Enum.join(data["supported_locales"] || ["en"], ", "),
           "timezone" => data["timezone"] || "UTC",
           "active" => true,
           "tagline" => data["tagline"] || "",
           "hero_image_url" => data["hero_image_url"] || ""
         })
         |> assign(:settings_json, settings_json)
         |> assign(:loading, false)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:inline_error, "Claude generation failed: #{inspect(reason)}. You can fill in manually.")}
    end
  end

  def handle_info({:suggest_cities, region_name, country_code}, socket) do
    case RegionBootstrap.suggest_cities(region_name, country_code) do
      {:ok, cities} ->
        cities = Enum.map(cities, &Map.put(&1, "selected", true))

        {:noreply,
         socket
         |> assign(:wizard_cities, cities)
         |> assign(:loading, false)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:inline_error, "City suggestions failed: #{inspect(reason)}")}
    end
  end

  def handle_info({:suggest_discovery_urls, region_id}, socket) do
    case RegionBootstrap.suggest_discovery_urls(region_id) do
      {:ok, url_groups} ->
        {:noreply,
         socket
         |> assign(:discovery_urls, url_groups)
         |> assign(:loading, false)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:inline_error, "URL suggestions failed: #{inspect(reason)}")}
    end
  end

  def handle_info({:suggest_discovery_urls_tavily, region_id}, socket) do
    case RegionBootstrap.suggest_discovery_urls_tavily(region_id) do
      {:ok, url_groups} ->
        {:noreply,
         socket
         |> assign(:discovery_urls, url_groups)
         |> assign(:loading, false)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:inline_error, "Tavily search failed: #{inspect(reason)}")}
    end
  end

  def handle_info({:start_osm_import, region_id}, socket) do
    case RegionBootstrap.start_overpass_import(region_id) do
      {:ok, result} ->
        {:noreply,
         socket
         |> assign(:osm_import_result, result)
         |> assign(:loading, false)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:inline_error, "OSM import failed: #{inspect(reason)}")}
    end
  end

  def handle_info({:start_crawling, url_groups, region_id}, socket) do
    case RegionBootstrap.start_discovery_crawls(url_groups, region_id) do
      {:ok, result} ->
        {:noreply,
         socket
         |> assign(:discovery_result, result)
         |> assign(:loading, false)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:inline_error, "Crawling failed: #{inspect(reason)}")}
    end
  end

  # --- Render ---

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200">
      <header class="bg-base-100 border-b border-base-300 sticky top-0 z-50 shadow-sm">
        <div class="container mx-auto px-6 py-3">
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-4">
              <.link navigate={~p"/admin"} class="btn btn-ghost btn-sm btn-circle">
                <span class="hero-arrow-left w-5 h-5"></span>
              </.link>
              <div>
                <h1 class="text-2xl font-bold">{gettext("Manage Regions")}</h1>
                <p class="text-base-content/60 text-sm">{gettext("Add and configure regions")}</p>
              </div>
            </div>
            <div class="flex items-center gap-2">
              <span class="text-sm text-base-content/70">{length(@regions)} {gettext("regions")}</span>
              <button type="button" phx-click="new" class="btn btn-primary btn-sm">
                <span class="hero-plus w-4 h-4"></span>
                {gettext("Add Region")}
              </button>
            </div>
          </div>
        </div>
      </header>

      <main class="container mx-auto max-w-4xl px-4 py-8">
        <div class="grid gap-4">
          <%= for region <- @regions do %>
            <div class="card bg-base-100 shadow-md">
              <div class="card-body py-4">
                <div class="flex items-center justify-between">
                  <div class="flex items-center gap-4">
                    <span class="text-3xl">{country_flag(region.country_code)}</span>
                    <div>
                      <div class="flex items-center gap-2">
                        <h3 class="font-bold text-lg">{region.name}</h3>
                        <span class="badge badge-ghost badge-sm font-mono">/{region.slug}</span>
                        <span class="badge badge-sm">{region.city_count} cities</span>
                        <%= if !region.active do %>
                          <span class="badge badge-warning badge-sm">{gettext("Inactive")}</span>
                        <% end %>
                      </div>
                      <p class="text-sm text-base-content/60">
                        {region.tagline || gettext("No tagline")}
                      </p>
                      <div class="flex items-center gap-3 mt-1">
                        <span class="text-xs text-base-content/40">
                          {gettext("Locales")}: {Enum.join(region.supported_locales || [], ", ")}
                        </span>
                        <span class="text-xs text-base-content/40">
                          {gettext("Timezone")}: {region.timezone}
                        </span>
                      </div>
                    </div>
                  </div>
                  <div class="flex items-center gap-1">
                    <%= if region.city_count > 0 do %>
                      <button type="button" phx-click="discover" phx-value-id={region.id} class="btn btn-ghost btn-sm">
                        <span class="hero-globe-alt w-4 h-4"></span>
                        {gettext("Discover")}
                      </button>
                    <% end %>
                    <button type="button" phx-click="edit" phx-value-id={region.id} class="btn btn-ghost btn-sm">
                      <span class="hero-pencil-square w-4 h-4"></span>
                      {gettext("Edit")}
                    </button>
                  </div>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </main>

      <%= if @wizard_step do %>
        <.wizard
          step={@wizard_step}
          wizard_name={@wizard_name}
          wizard_data={@wizard_data}
          wizard_cities={@wizard_cities}
          form_data={@form_data}
          settings_json={@settings_json}
          inline_error={@inline_error}
          loading={@loading}
          discovery_urls={@discovery_urls}
          discovery_result={@discovery_result}
          osm_import_result={@osm_import_result}
        />
      <% end %>

      <%= if @editing do %>
        <.edit_modal
          editing={@editing}
          form_data={@form_data}
          settings_json={@settings_json}
          inline_error={@inline_error}
          loading={@loading}
        />
      <% end %>
    </div>
    """
  end

  # --- Wizard component ---

  defp wizard(assigns) do
    ~H"""
    <div class="modal modal-open">
      <div class="modal-box max-w-4xl max-h-[90vh]">
        <div class="flex items-center justify-between mb-4">
          <div class="flex items-center gap-3">
            <.step_indicator step={@step} />
          </div>
          <%= if @loading do %>
            <span class="loading loading-spinner loading-sm text-primary"></span>
          <% end %>
        </div>

        <%= if @inline_error do %>
          <div class="alert alert-error alert-sm py-2 text-sm mb-4">
            <span class="hero-exclamation-circle w-4 h-4"></span>
            {@inline_error}
          </div>
        <% end %>

        <%= case @step do %>
          <% :name -> %>
            <.wizard_step_name wizard_name={@wizard_name} loading={@loading} />
          <% :review_region -> %>
            <.wizard_step_review_region form_data={@form_data} settings_json={@settings_json} loading={@loading} />
          <% :suggest_cities -> %>
            <.wizard_step_cities wizard_cities={@wizard_cities} loading={@loading} wizard_data={@wizard_data} />
          <% :discover -> %>
            <.wizard_step_discover wizard_data={@wizard_data} loading={@loading} discovery_urls={@discovery_urls} discovery_result={@discovery_result} osm_import_result={@osm_import_result} />
        <% end %>
      </div>
      <div class="modal-backdrop" phx-click="cancel"></div>
    </div>
    """
  end

  defp step_indicator(assigns) do
    steps = [
      {:name, "1", "Name"},
      {:review_region, "2", "Region"},
      {:suggest_cities, "3", "Cities"},
      {:discover, "4", "Discover"}
    ]

    assigns = assign(assigns, :steps, steps)

    ~H"""
    <ul class="steps steps-horizontal text-xs">
      <%= for {step_key, num, label} <- @steps do %>
        <li class={"step #{if step_active?(@step, step_key), do: "step-primary"}"}>{num}. {label}</li>
      <% end %>
    </ul>
    """
  end

  defp step_active?(current, target) do
    order = [:name, :review_region, :suggest_cities, :discover]
    current_idx = Enum.find_index(order, &(&1 == current)) || 0
    target_idx = Enum.find_index(order, &(&1 == target)) || 0
    current_idx >= target_idx
  end

  defp wizard_step_name(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="text-center py-4">
        <h3 class="text-xl font-bold mb-2">Create a New Region</h3>
        <p class="text-base-content/60">Enter a region or country name and Claude will generate all the details.</p>
      </div>

      <form phx-change="update_wizard_name" phx-submit="generate_region">
        <div class="form-control max-w-md mx-auto">
          <input
            type="text"
            name="name"
            value={@wizard_name}
            class="input input-bordered input-lg text-center"
            placeholder="e.g., Portugal"
            autofocus
            disabled={@loading}
          />
        </div>

        <div class="flex justify-center gap-3 mt-6">
          <button type="button" phx-click="cancel" class="btn btn-ghost btn-sm">Cancel</button>
          <button type="button" phx-click="skip_generate" class="btn btn-outline btn-sm" disabled={@loading}>
            Fill in manually
          </button>
          <button type="submit" class="btn btn-primary" disabled={@loading or @wizard_name == ""}>
            <%= if @loading do %>
              <span class="loading loading-spinner loading-xs"></span>
              Generating...
            <% else %>
              <span class="hero-sparkles w-5 h-5"></span>
              Generate with Claude
            <% end %>
          </button>
        </div>
      </form>
    </div>
    """
  end

  defp wizard_step_review_region(assigns) do
    ~H"""
    <form phx-submit="save_region_and_suggest_cities" phx-change="update_form" class="space-y-4 overflow-y-auto max-h-[70vh] pr-2">
      <div class="divider text-xs text-base-content/40 my-1">BASIC INFO</div>

      <div class="grid grid-cols-2 gap-4">
        <div>
          <label class="block text-sm font-medium mb-1">Name *</label>
          <input type="text" name="region[name]" value={@form_data["name"]} required class="input input-bordered w-full" />
        </div>
        <div>
          <label class="block text-sm font-medium mb-1">Slug *</label>
          <input type="text" name="region[slug]" value={@form_data["slug"]} required class="input input-bordered w-full font-mono" />
        </div>
      </div>

      <div class="grid grid-cols-3 gap-4">
        <div>
          <label class="block text-sm font-medium mb-1">Country Code *</label>
          <input type="text" name="region[country_code]" value={@form_data["country_code"]} required maxlength="2" class="input input-bordered w-full font-mono uppercase" />
        </div>
        <div>
          <label class="block text-sm font-medium mb-1">Default Locale</label>
          <input type="text" name="region[default_locale]" value={@form_data["default_locale"]} class="input input-bordered w-full font-mono" />
        </div>
        <div>
          <label class="block text-sm font-medium mb-1">Timezone</label>
          <input type="text" name="region[timezone]" value={@form_data["timezone"]} class="input input-bordered w-full font-mono text-sm" />
        </div>
      </div>

      <div>
        <label class="block text-sm font-medium mb-1">Supported Locales</label>
        <input type="text" name="region[supported_locales]" value={@form_data["supported_locales"]} class="input input-bordered w-full font-mono" />
        <p class="text-xs text-base-content/40 mt-1">Comma-separated locale codes</p>
      </div>

      <div class="divider text-xs text-base-content/40 my-1">DISPLAY</div>

      <div>
        <label class="block text-sm font-medium mb-1">Tagline</label>
        <input type="text" name="region[tagline]" value={@form_data["tagline"]} class="input input-bordered w-full" placeholder="Short evocative description" />
      </div>

      <div>
        <label class="block text-sm font-medium mb-1">Hero Image URL</label>
        <input type="text" name="region[hero_image_url]" value={@form_data["hero_image_url"]} class="input input-bordered w-full text-sm" placeholder="https://images.unsplash.com/..." />
      </div>

      <label class="flex items-center gap-3 cursor-pointer">
        <input type="hidden" name="region[active]" value="false" />
        <input type="checkbox" name="region[active]" value="true" checked={@form_data["active"]} class="checkbox checkbox-primary checkbox-sm" />
        <span class="text-sm">Active (visible to users)</span>
      </label>

      <div class="divider text-xs text-base-content/40 my-1">SETTINGS (JSON)</div>

      <div>
        <textarea
          name="region[settings_json]"
          rows="10"
          class="textarea textarea-bordered w-full font-mono text-xs"
        >{@settings_json}</textarea>
        <p class="text-xs text-base-content/40 mt-1">phrases, cultural_tips, enrichment_context</p>
      </div>

      <div class="modal-action">
        <button type="button" phx-click="cancel" class="btn btn-ghost btn-sm">Cancel</button>
        <button type="button" phx-click="save_region_only" class="btn btn-outline btn-sm">
          Save Region Only
        </button>
        <button type="submit" class="btn btn-primary btn-sm" disabled={@loading}>
          Save Region & Suggest Cities
          <span class="hero-arrow-right w-4 h-4"></span>
        </button>
      </div>
    </form>
    """
  end

  defp wizard_step_cities(assigns) do
    ~H"""
    <div class="space-y-4">
      <div>
        <h3 class="font-bold text-lg">Suggested Cities</h3>
        <p class="text-sm text-base-content/60">Review and select cities to add to the region.</p>
      </div>

      <%= if @loading do %>
        <div class="flex items-center justify-center py-8 gap-3">
          <span class="loading loading-spinner loading-md text-primary"></span>
          <span class="text-base-content/60">Claude is suggesting cities...</span>
        </div>
      <% else %>
        <div class="overflow-x-auto max-h-[50vh] overflow-y-auto">
          <table class="table table-sm table-zebra">
            <thead class="sticky top-0 bg-base-100">
              <tr>
                <th class="w-8"></th>
                <th>City</th>
                <th>Province</th>
                <th class="text-right">Population</th>
                <th class="text-center">Featured</th>
                <th class="text-right">Lat</th>
                <th class="text-right">Lon</th>
              </tr>
            </thead>
            <tbody>
              <%= for {city, index} <- Enum.with_index(@wizard_cities) do %>
                <tr class={"#{unless Map.get(city, "selected", true), do: "opacity-40"}"}>
                  <td>
                    <input
                      type="checkbox"
                      class="checkbox checkbox-xs"
                      checked={Map.get(city, "selected", true)}
                      phx-click="toggle_city"
                      phx-value-index={index}
                    />
                  </td>
                  <td class="font-medium">{city["name"]}</td>
                  <td class="text-sm">{city["province"]}</td>
                  <td class="text-right font-mono text-sm">{format_number(city["population"])}</td>
                  <td class="text-center">
                    <%= if city["featured"] do %>
                      <span class="hero-star w-4 h-4 text-warning"></span>
                    <% end %>
                  </td>
                  <td class="text-right font-mono text-xs">{format_coord(city["latitude"])}</td>
                  <td class="text-right font-mono text-xs">{format_coord(city["longitude"])}</td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>

        <div class="modal-action">
          <button type="button" phx-click="skip_cities" class="btn btn-ghost btn-sm">Skip</button>
          <button type="button" phx-click="create_cities" class="btn btn-primary btn-sm" disabled={@loading}>
            Create Cities & Continue
            <span class="hero-arrow-right w-4 h-4"></span>
          </button>
        </div>
      <% end %>
    </div>
    """
  end

  defp wizard_step_discover(assigns) do
    ~H"""
    <div class="space-y-4">
      <%= if @discovery_result do %>
        <%!-- Phase C: Crawling started --%>
        <div class="bg-success/10 rounded-lg p-6 text-center">
          <span class="hero-check-circle w-12 h-12 text-success mx-auto mb-3"></span>
          <p class="font-bold text-lg">Crawling Started!</p>
          <p class="text-base-content/60 mt-2">
            Started {@discovery_result.crawls_started} crawls across {@discovery_result.cities} cities.
          </p>
          <p class="text-sm text-base-content/40 mt-2">
            Pages will be saved for processing. The pipeline will handle
            extraction, enrichment, and translation automatically.
          </p>
        </div>

        <div class="modal-action">
          <button type="button" phx-click="finish" class="btn btn-ghost btn-sm">Close</button>
          <.link navigate={~p"/admin/pipeline"} class="btn btn-primary btn-sm">
            <span class="hero-queue-list w-4 h-4"></span>
            View Pipeline
          </.link>
        </div>

      <% else %>
        <div>
          <h3 class="font-bold text-lg">Discover Businesses</h3>
          <p class="text-sm text-base-content/60">
            Import from OpenStreetMap or find directory sites to crawl.
          </p>
        </div>

        <%= if @osm_import_result do %>
          <%!-- OSM import queued --%>
          <div class="bg-success/10 rounded-lg p-6 text-center">
            <span class="hero-check-circle w-12 h-12 text-success mx-auto mb-3"></span>
            <p class="font-bold text-lg">OpenStreetMap Import Queued!</p>
            <p class="text-base-content/60 mt-2">
              {@osm_import_result.jobs_queued} import jobs queued for {@osm_import_result.cities} cities.
            </p>
            <p class="text-sm text-base-content/40 mt-2">
              Jobs are staggered by 60 seconds to respect Overpass rate limits.
              Check the pipeline page for progress.
            </p>
          </div>

          <div class="divider text-xs text-base-content/40">Additionally</div>

          <p class="text-sm text-base-content/60 text-center">
            You can also find directory sites to crawl for more businesses.
          </p>
        <% end %>

        <%= if @discovery_urls == [] do %>
          <%!-- Phase A: Choose discovery method --%>
          <%= unless @osm_import_result do %>
            <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mt-2">
              <div class="card bg-base-200 border border-base-300">
                <div class="card-body items-center text-center py-6">
                  <span class="hero-map w-8 h-8 text-success"></span>
                  <h4 class="font-bold">OpenStreetMap</h4>
                  <p class="text-xs text-base-content/60">
                    Direct import from OSM. Free, structured data with addresses, phones, websites.
                  </p>
                  <button type="button" phx-click="start_osm_import" class="btn btn-success btn-sm mt-2" disabled={@loading}>
                    <%= if @loading do %>
                      <span class="loading loading-spinner loading-xs"></span>
                    <% else %>
                      <span class="hero-arrow-down-tray w-4 h-4"></span>
                    <% end %>
                    Import from OSM
                  </button>
                </div>
              </div>

              <div class="card bg-base-200 border border-base-300">
                <div class="card-body items-center text-center py-6">
                  <span class="hero-globe-alt w-8 h-8 text-info"></span>
                  <h4 class="font-bold">Directory Sites</h4>
                  <p class="text-xs text-base-content/60">
                    Search for real directory sites to crawl. Uses Tavily search API.
                  </p>
                  <button type="button" phx-click="suggest_urls_tavily" class="btn btn-info btn-sm mt-2" disabled={@loading}>
                    <%= if @loading do %>
                      <span class="loading loading-spinner loading-xs"></span>
                    <% else %>
                      <span class="hero-magnifying-glass w-4 h-4"></span>
                    <% end %>
                    Find Directory Sites
                  </button>
                </div>
              </div>
            </div>
          <% else %>
            <div class="flex justify-center">
              <button type="button" phx-click="suggest_urls_tavily" class="btn btn-info btn-sm" disabled={@loading}>
                <%= if @loading do %>
                  <span class="loading loading-spinner loading-xs"></span>
                  Searching...
                <% else %>
                  <span class="hero-magnifying-glass w-4 h-4"></span>
                  Find Directory Sites
                <% end %>
              </button>
            </div>
          <% end %>

          <div class="modal-action">
            <button type="button" phx-click="skip_discovery" class="btn btn-ghost btn-sm">Skip for now</button>
          </div>

        <% else %>
          <%!-- Phase B: Review URLs & start crawling --%>
          <div class="overflow-y-auto max-h-[55vh] space-y-3">
            <%= for {city_group, city_idx} <- Enum.with_index(@discovery_urls) do %>
              <div class="collapse collapse-open bg-base-200 rounded-lg">
                <div class="collapse-title text-sm font-bold py-2 min-h-0">
                  {city_group.city_name}
                  <span class="badge badge-ghost badge-xs ml-2">
                    {Enum.count(city_group.urls, &Map.get(&1, "selected", true))}/{length(city_group.urls)} selected
                  </span>
                </div>
                <div class="collapse-content px-3 pb-2">
                  <div class="space-y-1">
                    <%= for {url_entry, url_idx} <- Enum.with_index(city_group.urls) do %>
                      <label class={"flex items-start gap-2 p-2 rounded cursor-pointer hover:bg-base-300 #{unless Map.get(url_entry, "selected", true), do: "opacity-40"}"}>
                        <input
                          type="checkbox"
                          class="checkbox checkbox-xs mt-0.5"
                          checked={Map.get(url_entry, "selected", true)}
                          phx-click="toggle_url"
                          phx-value-city={city_idx}
                          phx-value-url={url_idx}
                        />
                        <div class="flex-1 min-w-0">
                          <p class="text-sm font-medium truncate">{url_entry["name"]}</p>
                          <p class="text-xs text-base-content/50 truncate">{url_entry["url"]}</p>
                          <p class="text-xs text-base-content/40">{url_entry["description"]}</p>
                        </div>
                      </label>
                    <% end %>
                  </div>
                </div>
              </div>
            <% end %>
          </div>

          <div class="bg-base-200 rounded-lg p-3 text-sm">
            <p class="text-base-content/60">
              <span class="font-medium">Free:</span>
              Crawly will crawl the selected URLs to discover businesses. No API costs.
            </p>
          </div>

          <div class="modal-action">
            <button type="button" phx-click="skip_discovery" class="btn btn-ghost btn-sm">Skip</button>
            <button type="button" phx-click="start_crawling" class="btn btn-primary btn-sm" disabled={@loading}>
              <%= if @loading do %>
                <span class="loading loading-spinner loading-xs"></span>
                Starting crawls...
              <% else %>
                <span class="hero-globe-alt w-4 h-4"></span>
                Start Crawling
              <% end %>
            </button>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  # --- Edit modal (for existing regions) ---

  defp edit_modal(assigns) do
    ~H"""
    <div class="modal modal-open">
      <div class="modal-box max-w-3xl">
        <h3 class="font-bold text-xl mb-4">Edit Region</h3>

        <%= if @inline_error do %>
          <div class="alert alert-error alert-sm py-2 text-sm mb-4">
            <span class="hero-exclamation-circle w-4 h-4"></span>
            {@inline_error}
          </div>
        <% end %>

        <form phx-submit="save" phx-change="update_form" class="space-y-4">
          <div class="grid grid-cols-2 gap-4">
            <div>
              <label class="block text-sm font-medium mb-1">Name *</label>
              <input type="text" name="region[name]" value={@form_data["name"]} required class="input input-bordered w-full" />
            </div>
            <div>
              <label class="block text-sm font-medium mb-1">Slug</label>
              <input type="text" name="region[slug]" value={@form_data["slug"]} class="input input-bordered w-full font-mono" disabled />
            </div>
          </div>

          <div class="grid grid-cols-3 gap-4">
            <div>
              <label class="block text-sm font-medium mb-1">Country Code</label>
              <input type="text" value={@form_data["country_code"]} class="input input-bordered w-full font-mono" disabled />
            </div>
            <div>
              <label class="block text-sm font-medium mb-1">Default Locale</label>
              <input type="text" name="region[default_locale]" value={@form_data["default_locale"]} class="input input-bordered w-full font-mono" />
            </div>
            <div>
              <label class="block text-sm font-medium mb-1">Timezone</label>
              <input type="text" name="region[timezone]" value={@form_data["timezone"]} class="input input-bordered w-full font-mono text-sm" />
            </div>
          </div>

          <div>
            <label class="block text-sm font-medium mb-1">Supported Locales</label>
            <input type="text" name="region[supported_locales]" value={@form_data["supported_locales"]} class="input input-bordered w-full font-mono" />
          </div>

          <label class="flex items-center gap-3 cursor-pointer">
            <input type="hidden" name="region[active]" value="false" />
            <input type="checkbox" name="region[active]" value="true" checked={@form_data["active"]} class="checkbox checkbox-primary checkbox-sm" />
            <span class="text-sm">Active (visible to users)</span>
          </label>

          <div>
            <label class="block text-sm font-medium mb-1">Tagline</label>
            <input type="text" name="region[tagline]" value={@form_data["tagline"]} class="input input-bordered w-full" />
          </div>

          <div>
            <label class="block text-sm font-medium mb-1">Hero Image URL</label>
            <input type="text" name="region[hero_image_url]" value={@form_data["hero_image_url"]} class="input input-bordered w-full text-sm" />
          </div>

          <div>
            <label class="block text-sm font-medium mb-1">Settings (JSON)</label>
            <textarea name="region[settings_json]" rows="10" class="textarea textarea-bordered w-full font-mono text-xs">{@settings_json}</textarea>
          </div>

          <div class="modal-action">
            <button type="button" phx-click="cancel" class="btn btn-ghost btn-sm">Cancel</button>
            <button type="submit" class="btn btn-primary btn-sm">Save Changes</button>
          </div>
        </form>
      </div>
      <div class="modal-backdrop" phx-click="cancel"></div>
    </div>
    """
  end

  # --- Helpers ---

  defp save_region(socket, params) do
    settings_json = params["settings_json"] || socket.assigns.settings_json

    settings =
      case Jason.decode(settings_json) do
        {:ok, map} when is_map(map) -> map
        _ -> nil
      end

    if is_nil(settings) do
      {:error, "Invalid JSON in settings field"}
    else
      locales = parse_locales(params["supported_locales"])

      attrs = %{
        name: params["name"],
        slug: params["slug"],
        country_code: params["country_code"],
        default_locale: params["default_locale"] || "en",
        supported_locales: locales,
        timezone: params["timezone"] || "UTC",
        active: params["active"] == "true",
        tagline: params["tagline"],
        hero_image_url: params["hero_image_url"],
        settings: settings
      }

      case Region.create(attrs) do
        {:ok, region} ->
          clear_region_cache()
          {:ok, region}

        {:error, error} ->
          {:error, format_error(error)}
      end
    end
  end

  defp save_existing_region(socket, params) do
    settings_json = params["settings_json"] || socket.assigns.settings_json

    settings =
      case Jason.decode(settings_json) do
        {:ok, map} when is_map(map) -> map
        _ -> nil
      end

    if is_nil(settings) do
      {:error, "Invalid JSON in settings field"}
    else
      locales = parse_locales(params["supported_locales"])

      attrs = %{
        name: params["name"],
        default_locale: params["default_locale"] || "en",
        supported_locales: locales,
        timezone: params["timezone"] || "UTC",
        active: params["active"] == "true",
        tagline: params["tagline"],
        hero_image_url: params["hero_image_url"],
        settings: settings
      }

      case Ash.update(socket.assigns.editing, attrs, action: :update) do
        {:ok, region} ->
          clear_region_cache()
          {:ok, region}

        {:error, error} ->
          {:error, format_error(error)}
      end
    end
  end

  defp parse_locales(locales_str) do
    (locales_str || "en")
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp clear_region_cache do
    try do
      :persistent_term.erase(:known_region_slugs)
    rescue
      _ -> :ok
    end
  end

  defp format_error(%Ash.Error.Invalid{} = e), do: Ash.Error.Invalid.message(e)
  defp format_error(other), do: inspect(other)

  defp slugify(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/\s+/, "-")
    |> String.trim("-")
  end

  defp format_number(nil), do: "-"
  defp format_number(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})/, "\\1,")
    |> String.reverse()
    |> String.trim_leading(",")
  end
  defp format_number(n), do: "#{n}"

  defp format_coord(nil), do: "-"
  defp format_coord(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 4)
  defp format_coord(n) when is_integer(n), do: :erlang.float_to_binary(n / 1, decimals: 4)
  defp format_coord(n), do: "#{n}"

  defp country_flag(country_code) when is_binary(country_code) and byte_size(country_code) == 2 do
    country_code
    |> String.upcase()
    |> String.to_charlist()
    |> Enum.map(&(&1 - ?A + 0x1F1E6))
    |> List.to_string()
  end

  defp country_flag(_), do: "🌍"
end
