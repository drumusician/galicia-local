defmodule GaliciaLocalWeb.Admin.RegionsLive do
  @moduledoc """
  Admin page for managing regions.
  Allows creating new regions and editing existing ones.
  """
  use GaliciaLocalWeb, :live_view

  alias GaliciaLocal.Directory.Region

  @impl true
  def mount(_params, _session, socket) do
    regions = Region.list!()

    {:ok,
     socket
     |> assign(:page_title, "Manage Regions")
     |> assign(:regions, regions)
     |> assign(:editing, nil)
     |> assign(:form_data, %{})
     |> assign(:inline_error, nil)
     |> assign(:loading, false)
     |> assign(:settings_json, "{}")}
  end

  @impl true
  def handle_event("new", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing, :new)
     |> assign(:form_data, %{
       "name" => "",
       "slug" => "",
       "country_code" => "",
       "default_locale" => "en",
       "supported_locales" => "en",
       "timezone" => "UTC",
       "active" => true,
       "tagline" => "",
       "hero_image_url" => ""
     })
     |> assign(:settings_json, "{\n  \"phrases\": [],\n  \"cultural_tips\": [],\n  \"enrichment_context\": {}\n}")
     |> assign(:inline_error, nil)}
  end

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
    {:noreply, assign(socket, :editing, nil)}
  end

  def handle_event("update_form", %{"region" => params}, socket) do
    form_data =
      socket.assigns.form_data
      |> Map.merge(params)
      |> Map.put("active", params["active"] == "true")

    {:noreply, assign(socket, :form_data, form_data)}
  end

  def handle_event("update_settings_json", %{"settings_json" => json}, socket) do
    {:noreply, assign(socket, :settings_json, json)}
  end

  def handle_event("save", %{"region" => params}, socket) do
    settings_json = socket.assigns.settings_json

    settings =
      case Jason.decode(settings_json) do
        {:ok, map} when is_map(map) -> map
        _ -> nil
      end

    if is_nil(settings) do
      {:noreply, assign(socket, :inline_error, "Invalid JSON in settings field")}
    else
      locales =
        (params["supported_locales"] || "en")
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

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

      result =
        case socket.assigns.editing do
          :new -> Region.create(attrs)
          region -> Ash.update(region, :update, params: attrs)
        end

      case result do
        {:ok, _region} ->
          regions = Region.list!()
          # Clear persistent_term cache so SetRegion plug picks up new regions
          try do
            :persistent_term.erase(:known_region_slugs)
          rescue
            _ -> :ok
          end

          {:noreply,
           socket
           |> assign(:regions, regions)
           |> assign(:editing, nil)
           |> put_flash(:info, "Region saved successfully")}

        {:error, error} ->
          message =
            case error do
              %Ash.Error.Invalid{} = e -> Ash.Error.Invalid.message(e)
              other -> inspect(other)
            end

          {:noreply, assign(socket, :inline_error, message)}
      end
    end
  end

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
                  <button type="button" phx-click="edit" phx-value-id={region.id} class="btn btn-ghost btn-sm">
                    <span class="hero-pencil-square w-4 h-4"></span>
                    {gettext("Edit")}
                  </button>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </main>

      <%= if @editing do %>
        <.region_modal
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

  defp region_modal(assigns) do
    assigns = assign(assigns, :title, if(assigns.editing == :new, do: "New Region", else: "Edit Region"))

    ~H"""
    <div class="modal modal-open">
      <div class="modal-box max-w-3xl">
        <div class="flex items-center justify-between mb-4">
          <h3 class="font-bold text-xl">{@title}</h3>
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

        <form phx-submit="save" phx-change="update_form" class="space-y-4">
          <div class="divider text-xs text-base-content/40 my-1">BASIC INFO</div>

          <div class="grid grid-cols-2 gap-4">
            <div>
              <label class="block text-sm font-medium mb-1">Name *</label>
              <input
                type="text"
                name="region[name]"
                value={@form_data["name"]}
                required
                class="input input-bordered w-full"
                placeholder="e.g., Portugal"
              />
            </div>
            <div>
              <label class="block text-sm font-medium mb-1">Slug *</label>
              <input
                type="text"
                name="region[slug]"
                value={@form_data["slug"]}
                required
                class="input input-bordered w-full font-mono"
                placeholder="e.g., portugal"
                disabled={@editing != :new}
              />
            </div>
          </div>

          <div class="grid grid-cols-3 gap-4">
            <div>
              <label class="block text-sm font-medium mb-1">Country Code *</label>
              <input
                type="text"
                name="region[country_code]"
                value={@form_data["country_code"]}
                required
                maxlength="2"
                class="input input-bordered w-full font-mono uppercase"
                placeholder="e.g., PT"
              />
            </div>
            <div>
              <label class="block text-sm font-medium mb-1">Default Locale</label>
              <input
                type="text"
                name="region[default_locale]"
                value={@form_data["default_locale"]}
                class="input input-bordered w-full font-mono"
                placeholder="en"
              />
            </div>
            <div>
              <label class="block text-sm font-medium mb-1">Timezone</label>
              <input
                type="text"
                name="region[timezone]"
                value={@form_data["timezone"]}
                class="input input-bordered w-full font-mono text-sm"
                placeholder="Europe/Lisbon"
              />
            </div>
          </div>

          <div>
            <label class="block text-sm font-medium mb-1">Supported Locales</label>
            <input
              type="text"
              name="region[supported_locales]"
              value={@form_data["supported_locales"]}
              class="input input-bordered w-full font-mono"
              placeholder="en, pt, es"
            />
            <p class="text-xs text-base-content/40 mt-1">Comma-separated locale codes</p>
          </div>

          <label class="flex items-center gap-3 cursor-pointer">
            <input
              type="hidden"
              name="region[active]"
              value="false"
            />
            <input
              type="checkbox"
              name="region[active]"
              value="true"
              checked={@form_data["active"]}
              class="checkbox checkbox-primary checkbox-sm"
            />
            <span class="text-sm">Active (visible to users)</span>
          </label>

          <div class="divider text-xs text-base-content/40 my-1">DISPLAY</div>

          <div>
            <label class="block text-sm font-medium mb-1">Tagline</label>
            <input
              type="text"
              name="region[tagline]"
              value={@form_data["tagline"]}
              class="input input-bordered w-full"
              placeholder="e.g., Sun-soaked coastlines, authentic cuisine"
            />
          </div>

          <div>
            <label class="block text-sm font-medium mb-1">Hero Image URL</label>
            <input
              type="text"
              name="region[hero_image_url]"
              value={@form_data["hero_image_url"]}
              class="input input-bordered w-full text-sm"
              placeholder="https://images.unsplash.com/..."
            />
          </div>

          <div class="divider text-xs text-base-content/40 my-1">SETTINGS (JSON)</div>

          <div>
            <label class="block text-sm font-medium mb-1">Settings</label>
            <textarea
              name="settings_json"
              rows="12"
              phx-change="update_settings_json"
              class="textarea textarea-bordered w-full font-mono text-xs"
              placeholder='{"phrases": [], "cultural_tips": [], "enrichment_context": {}}'
            >{@settings_json}</textarea>
            <p class="text-xs text-base-content/40 mt-1">
              JSON with phrases, cultural_tips, and enrichment_context
            </p>
          </div>

          <div class="modal-action">
            <button type="button" phx-click="cancel" class="btn btn-ghost btn-sm">Cancel</button>
            <button type="submit" class="btn btn-primary btn-sm" disabled={@loading}>
              <%= if @editing == :new, do: "Create Region", else: "Save Changes" %>
            </button>
          </div>
        </form>
      </div>
      <div class="modal-backdrop" phx-click="cancel"></div>
    </div>
    """
  end

  defp country_flag(country_code) when is_binary(country_code) and byte_size(country_code) == 2 do
    country_code
    |> String.upcase()
    |> String.to_charlist()
    |> Enum.map(&(&1 - ?A + 0x1F1E6))
    |> List.to_string()
  end

  defp country_flag(_), do: "🌍"
end
