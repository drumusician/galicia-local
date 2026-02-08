defmodule GaliciaLocalWeb.Admin.EditBusinessLive do
  @moduledoc """
  Admin full-page editor for business listings with tabbed translations.
  Supports multiple languages with auto-translate functionality.
  """
  use GaliciaLocalWeb, :live_view

  alias GaliciaLocal.Directory.{Business, BusinessTranslation, City, Category}
  alias GaliciaLocal.Directory.Business.Quality

  @days ~w(monday tuesday wednesday thursday friday saturday sunday)
  @supported_locales [
    {"en", "English", "🇬🇧"},
    {"es", "Español", "🇪🇸"},
    {"nl", "Nederlands", "🇳🇱"}
  ]
  @translatable_fields ~w(description summary highlights warnings integration_tips cultural_notes)a

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    region = socket.assigns[:current_region]
    region_slug = if region, do: region.slug, else: "galicia"

    case Business.get_by_id(id) do
      {:ok, business} ->
        business = Ash.load!(business, [:city, :category, :translations])
        cities = City.list!() |> Enum.sort_by(& &1.name)
        categories = Category.list!() |> Enum.sort_by(& &1.name)

        # Build translation map keyed by locale
        translations_map = build_translations_map(business)

        {:ok,
         socket
         |> assign(:page_title, "Edit: #{business.name}")
         |> assign(:business, business)
         |> assign(:cities, cities)
         |> assign(:categories, categories)
         |> assign(:region_slug, region_slug)
         |> assign(:supported_locales, @supported_locales)
         |> assign(:translations_map, translations_map)
         |> assign(:active_locale, "en")
         |> assign(:translating, nil)
         |> assign(:saving, false)
         |> assign(:quality_score, Quality.score(business))
         |> assign(:quality_checklist, Quality.checklist(business))
         |> assign(:google_places_results, nil)
         |> assign(:google_places_loading, false)
         |> assign(:google_places_enriching, false)}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, "Business not found")
         |> push_navigate(to: ~p"/admin/businesses")}
    end
  end

  defp build_translations_map(business) do
    # Start with English from the business itself
    base = %{
      "en" => %{
        description: business.description,
        summary: business.summary,
        highlights: business.highlights || [],
        warnings: business.warnings || [],
        integration_tips: business.integration_tips || [],
        cultural_notes: business.cultural_notes || []
      }
    }

    # Add translations from the translations table
    Enum.reduce(business.translations || [], base, fn translation, acc ->
      Map.put(acc, translation.locale, %{
        description: translation.description,
        summary: translation.summary,
        highlights: translation.highlights || [],
        warnings: translation.warnings || [],
        integration_tips: translation.integration_tips || [],
        cultural_notes: translation.cultural_notes || []
      })
    end)
  end

  @impl true
  def handle_event("save", %{"business" => params}, socket) do
    socket = assign(socket, :saving, true)
    business = socket.assigns.business
    params = parse_array_fields(params)
    params = parse_opening_hours(params)

    case Ash.update(business, params) do
      {:ok, updated} ->
        updated = Ash.load!(updated, [:city, :category, :translations])

        {:noreply,
         socket
         |> assign(:business, updated)
         |> assign(:translations_map, build_translations_map(updated))
         |> assign(:quality_score, Quality.score(updated))
         |> assign(:quality_checklist, Quality.checklist(updated))
         |> assign(:saving, false)
         |> put_flash(:info, "Business updated successfully")}

      {:error, _} ->
        {:noreply,
         socket
         |> assign(:saving, false)
         |> put_flash(:error, "Failed to update business")}
    end
  end

  @impl true
  def handle_event("switch_locale", %{"locale" => locale}, socket) do
    {:noreply, assign(socket, :active_locale, locale)}
  end

  @impl true
  def handle_event("save_translation", %{"translation" => params}, socket) do
    business = socket.assigns.business
    locale = socket.assigns.active_locale

    # Don't save to translation table for English - that stays in the business
    if locale == "en" do
      # Update the business directly
      business_params = %{
        "description" => params["description"],
        "summary" => params["summary"],
        "highlights" => parse_textarea_to_list(params["highlights"]),
        "warnings" => parse_textarea_to_list(params["warnings"]),
        "integration_tips" => parse_textarea_to_list(params["integration_tips"]),
        "cultural_notes" => parse_textarea_to_list(params["cultural_notes"])
      }

      case Ash.update(business, business_params) do
        {:ok, updated} ->
          updated = Ash.load!(updated, [:city, :category, :translations])
          {:noreply,
           socket
           |> assign(:business, updated)
           |> assign(:translations_map, build_translations_map(updated))
           |> put_flash(:info, "English content saved")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to save")}
      end
    else
      # Upsert to translation table
      translation_params = %{
        business_id: business.id,
        locale: locale,
        description: params["description"],
        summary: params["summary"],
        highlights: parse_textarea_to_list(params["highlights"]),
        warnings: parse_textarea_to_list(params["warnings"]),
        integration_tips: parse_textarea_to_list(params["integration_tips"]),
        cultural_notes: parse_textarea_to_list(params["cultural_notes"])
      }

      case BusinessTranslation.upsert(translation_params) do
        {:ok, _} ->
          # Reload business with translations
          {:ok, updated} = Business.get_by_id(business.id)
          updated = Ash.load!(updated, [:city, :category, :translations])
          {:noreply,
           socket
           |> assign(:business, updated)
           |> assign(:translations_map, build_translations_map(updated))
           |> put_flash(:info, "#{locale_name(locale)} translation saved")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to save translation")}
      end
    end
  end

  @impl true
  def handle_event("translate_field", %{"field" => field}, socket) do
    socket = assign(socket, :translating, field)
    send(self(), {:do_translate, field})
    {:noreply, socket}
  end

  @impl true
  def handle_event("translate_all", _params, socket) do
    socket = assign(socket, :translating, "all")
    send(self(), {:do_translate_all})
    {:noreply, socket}
  end

  @impl true
  def handle_event("search_google_places", _params, socket) do
    socket = assign(socket, google_places_loading: true, google_places_results: nil)
    send(self(), :do_search_google_places)
    {:noreply, socket}
  end

  @impl true
  def handle_event("select_google_place", %{"place-id" => place_id}, socket) do
    socket = assign(socket, google_places_enriching: true)
    send(self(), {:do_enrich_google_places, place_id})
    {:noreply, socket}
  end

  @impl true
  def handle_event("dismiss_google_places", _params, socket) do
    {:noreply, assign(socket, google_places_results: nil)}
  end

  @impl true
  def handle_event("enrich_with_llm", _params, socket) do
    socket = assign(socket, saving: true)
    send(self(), :do_enrich_with_llm)
    {:noreply, socket}
  end

  @impl true
  def handle_event("queue_re_enrichment", _params, socket) do
    business = socket.assigns.business

    case Ash.update(business, %{status: :researched}, action: :queue_re_enrichment) do
      {:ok, updated} ->
        updated = Ash.load!(updated, [:city, :category, :translations])

        {:noreply,
         socket
         |> assign(:business, updated)
         |> put_flash(:info, "Queued for re-enrichment. Oban will pick it up.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to queue re-enrichment")}
    end
  end

  @impl true
  def handle_info({:do_translate, field}, socket) do
    business = socket.assigns.business
    target_locale = socket.assigns.active_locale
    translations_map = socket.assigns.translations_map

    # Get English source
    english_content = get_in(translations_map, ["en", String.to_existing_atom(field)])

    if english_content && english_content != "" && english_content != [] do
      case translate_content(business.name, field, english_content, target_locale) do
        {:ok, translated} ->
          # Update the translations map
          current = Map.get(translations_map, target_locale, %{})
          updated = Map.put(current, String.to_existing_atom(field), translated)
          new_map = Map.put(translations_map, target_locale, updated)

          {:noreply,
           socket
           |> assign(:translations_map, new_map)
           |> assign(:translating, nil)
           |> put_flash(:info, "#{field} translated to #{locale_name(target_locale)}")}

        {:error, reason} ->
          {:noreply,
           socket
           |> assign(:translating, nil)
           |> put_flash(:error, "Translation failed: #{reason}")}
      end
    else
      {:noreply,
       socket
       |> assign(:translating, nil)
       |> put_flash(:warning, "No English content to translate")}
    end
  end

  @impl true
  def handle_info({:do_translate_all}, socket) do
    business = socket.assigns.business
    target_locale = socket.assigns.active_locale
    translations_map = socket.assigns.translations_map
    english = Map.get(translations_map, "en", %{})

    # Collect all non-empty fields
    fields_to_translate =
      @translatable_fields
      |> Enum.filter(fn field ->
        value = Map.get(english, field)
        value && value != "" && value != []
      end)

    if Enum.empty?(fields_to_translate) do
      {:noreply,
       socket
       |> assign(:translating, nil)
       |> put_flash(:warning, "No English content to translate")}
    else
      case translate_all_fields(business.name, english, fields_to_translate, target_locale) do
        {:ok, translated_map} ->
          current = Map.get(translations_map, target_locale, %{})
          updated = Map.merge(current, translated_map)
          new_map = Map.put(translations_map, target_locale, updated)

          {:noreply,
           socket
           |> assign(:translations_map, new_map)
           |> assign(:translating, nil)
           |> put_flash(:info, "All fields translated to #{locale_name(target_locale)}")}

        {:error, reason} ->
          {:noreply,
           socket
           |> assign(:translating, nil)
           |> put_flash(:error, "Translation failed: #{reason}")}
      end
    end
  end

  @impl true
  def handle_info(:do_search_google_places, socket) do
    business = socket.assigns.business
    city_name = if business.city, do: business.city.name, else: ""
    query = "#{business.name} #{city_name}"

    location_opts =
      if business.latitude && business.longitude do
        [location: {business.latitude, business.longitude}, radius: 5000]
      else
        []
      end

    case GaliciaLocal.Scraper.GooglePlaces.search(query, location_opts) do
      {:ok, results} ->
        {:noreply,
         socket
         |> assign(:google_places_results, Enum.take(results, 5))
         |> assign(:google_places_loading, false)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:google_places_loading, false)
         |> assign(:google_places_results, nil)
         |> put_flash(:error, "Google Places search failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_info({:do_enrich_google_places, place_id}, socket) do
    business = socket.assigns.business

    case Business.enrich_with_google_places(business, place_id) do
      {:ok, updated} ->
        updated = Ash.load!(updated, [:city, :category, :translations])

        {:noreply,
         socket
         |> assign(:business, updated)
         |> assign(:translations_map, build_translations_map(updated))
         |> assign(:quality_score, Quality.score(updated))
         |> assign(:quality_checklist, Quality.checklist(updated))
         |> assign(:google_places_enriching, false)
         |> assign(:google_places_results, nil)
         |> put_flash(:info, "Google Places data merged successfully")}

      {:error, error} ->
        {:noreply,
         socket
         |> assign(:google_places_enriching, false)
         |> put_flash(:error, "Enrichment failed: #{inspect(error)}")}
    end
  end

  @impl true
  def handle_info(:do_enrich_with_llm, socket) do
    business = socket.assigns.business

    case Business.enrich_with_llm(business) do
      {:ok, updated} ->
        updated = Ash.load!(updated, [:city, :category, :translations])

        {:noreply,
         socket
         |> assign(:business, updated)
         |> assign(:translations_map, build_translations_map(updated))
         |> assign(:quality_score, Quality.score(updated))
         |> assign(:quality_checklist, Quality.checklist(updated))
         |> assign(:saving, false)
         |> put_flash(:info, "AI enrichment complete")}

      {:error, error} ->
        {:noreply,
         socket
         |> assign(:saving, false)
         |> put_flash(:error, "AI enrichment failed: #{inspect(error)}")}
    end
  end

  # Translation helpers (using DeepL)

  defp translate_content(_business_name, _field, content, target_locale) when is_list(content) do
    GaliciaLocal.AI.DeepL.translate_batch(content, target_locale, source_lang: "en")
  end

  defp translate_content(_business_name, _field, content, target_locale) do
    GaliciaLocal.AI.DeepL.translate(content, target_locale, source_lang: "en")
  end

  defp translate_all_fields(_business_name, english_content, fields, target_locale) do
    {string_fields, array_fields} =
      Enum.split_with(fields, fn field ->
        is_binary(Map.get(english_content, field))
      end)

    string_keys = Enum.map(string_fields, fn f -> f end)
    string_values = Enum.map(string_fields, fn f -> Map.get(english_content, f) end)

    array_meta = Enum.map(array_fields, fn f -> {f, length(Map.get(english_content, f, []))} end)
    array_values = Enum.flat_map(array_fields, fn f -> Map.get(english_content, f, []) end)

    all_texts = string_values ++ array_values

    case GaliciaLocal.AI.DeepL.translate_batch(all_texts, target_locale, source_lang: "en") do
      {:ok, translated_all} ->
        {translated_strings, translated_arrays_flat} = Enum.split(translated_all, length(string_values))

        string_result = Enum.zip(string_keys, translated_strings) |> Map.new()

        {array_result, _rest} =
          Enum.reduce(array_meta, {%{}, translated_arrays_flat}, fn {key, count}, {acc, remaining} ->
            {items, rest} = Enum.split(remaining, count)
            {Map.put(acc, key, items), rest}
          end)

        {:ok, Map.merge(string_result, array_result)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp locale_name("en"), do: "English"
  defp locale_name("es"), do: "Spanish"
  defp locale_name("nl"), do: "Dutch"
  defp locale_name(code), do: code

  # Form parsing helpers

  defp parse_array_fields(params) do
    array_keys = ~w(highlights warnings
      integration_tips cultural_notes
      service_specialties languages_taught expat_tips photo_urls)

    Enum.reduce(array_keys, params, fn key, acc ->
      case acc[key] do
        nil -> acc
        "" -> Map.put(acc, key, [])
        text when is_binary(text) -> Map.put(acc, key, parse_textarea_to_list(text))
        _ -> acc
      end
    end)
  end

  defp parse_textarea_to_list(nil), do: []
  defp parse_textarea_to_list(""), do: []
  defp parse_textarea_to_list(text) when is_binary(text) do
    text
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end
  defp parse_textarea_to_list(list) when is_list(list), do: list

  defp parse_opening_hours(params) do
    case params["opening_hours"] do
      nil -> params
      hours ->
        parsed =
          Enum.reduce(@days, %{}, fn day, acc ->
            case hours[day] do
              nil -> acc
              "" -> acc
              val when is_binary(val) -> Map.put(acc, day, String.trim(val))
              _ -> acc
            end
          end)
        Map.put(params, "opening_hours", parsed)
    end
  end

  defp format_array(nil), do: ""
  defp format_array(list) when is_list(list), do: Enum.join(list, "\n")
  defp format_array(_), do: ""

  defp get_day_hours(business, day) do
    case business.opening_hours do
      %{^day => val} when is_binary(val) -> val
      %{^day => %{"closed" => true}} -> "Closed"
      %{^day => %{"open" => open, "close" => close}} -> "#{open} - #{close}"
      _ -> ""
    end
  end

  defp day_label(day), do: String.capitalize(day)

  defp has_translation?(translations_map, locale) do
    case Map.get(translations_map, locale) do
      nil -> false
      data ->
        Enum.any?(@translatable_fields, fn field ->
          value = Map.get(data, field)
          value && value != "" && value != []
        end)
    end
  end

  defp get_translation_field(translations_map, locale, field) do
    get_in(translations_map, [locale, field]) || ""
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :days, @days)

    ~H"""
    <div class="min-h-screen bg-base-200">
      <!-- Sticky Header -->
      <header class="bg-base-100 border-b border-base-300 sticky top-0 z-50 shadow-sm">
        <div class="container mx-auto px-6 py-3">
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-4">
              <.link navigate={~p"/admin/businesses"} class="btn btn-ghost btn-sm btn-circle">
                <span class="hero-arrow-left w-5 h-5"></span>
              </.link>
              <div>
                <h1 class="text-lg font-bold">{@business.name}</h1>
                <p class="text-sm text-base-content/60">
                  {if @business.category, do: @business.category.name, else: "—"} · {if @business.city, do: @business.city.name, else: "—"}
                </p>
              </div>
            </div>
            <div class="flex items-center gap-3">
              <span class={["badge", status_class(@business.status)]}>{@business.status}</span>
              <.link navigate={~p"/#{@region_slug}/businesses/#{@business.id}"} class="btn btn-ghost btn-sm">
                <span class="hero-eye w-4 h-4"></span> View
              </.link>
            </div>
          </div>
        </div>
      </header>

      <main class="container mx-auto max-w-5xl px-6 py-8">
        <form phx-submit="save" class="space-y-6">
          <!-- Basic Info Card -->
          <div class="card bg-base-100 shadow-lg">
            <div class="card-body">
              <h2 class="card-title text-lg flex items-center gap-2">
                <span class="hero-building-office w-5 h-5 text-primary"></span>
                Basic Information
              </h2>

              <div class="grid grid-cols-1 md:grid-cols-3 gap-4 mt-4">
                <div class="form-control">
                  <label class="label"><span class="label-text font-medium">Name</span></label>
                  <input type="text" name="business[name]" value={@business.name} class="input input-bordered w-full" required />
                </div>
                <div class="form-control">
                  <label class="label"><span class="label-text font-medium">City</span></label>
                  <select name="business[city_id]" class="select select-bordered w-full">
                    <%= for city <- @cities do %>
                      <option value={city.id} selected={@business.city_id == city.id}>{city.name}</option>
                    <% end %>
                  </select>
                </div>
                <div class="form-control">
                  <label class="label"><span class="label-text font-medium">Category</span></label>
                  <select name="business[category_id]" class="select select-bordered w-full">
                    <%= for cat <- @categories do %>
                      <option value={cat.id} selected={@business.category_id == cat.id}>{cat.name}</option>
                    <% end %>
                  </select>
                </div>
              </div>

              <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mt-2">
                <div class="form-control">
                  <label class="label"><span class="label-text font-medium">Address</span></label>
                  <input type="text" name="business[address]" value={@business.address} class="input input-bordered w-full" />
                </div>
                <div class="form-control">
                  <label class="label"><span class="label-text font-medium">Phone</span></label>
                  <input type="text" name="business[phone]" value={@business.phone} class="input input-bordered w-full" />
                </div>
                <div class="form-control">
                  <label class="label"><span class="label-text font-medium">Email</span></label>
                  <input type="email" name="business[email]" value={@business.email} class="input input-bordered w-full" />
                </div>
                <div class="form-control">
                  <label class="label"><span class="label-text font-medium">Website</span></label>
                  <input type="url" name="business[website]" value={@business.website} class="input input-bordered w-full" />
                </div>
              </div>

              <div class="grid grid-cols-2 md:grid-cols-4 gap-4 mt-2">
                <div class="form-control">
                  <label class="label"><span class="label-text font-medium">Status</span></label>
                  <select name="business[status]" class="select select-bordered w-full">
                    <option value="pending" selected={@business.status == :pending}>Pending</option>
                    <option value="researching" selected={@business.status == :researching}>Researching</option>
                    <option value="researched" selected={@business.status == :researched}>Researched</option>
                    <option value="enriched" selected={@business.status == :enriched}>Enriched</option>
                    <option value="verified" selected={@business.status == :verified}>Verified</option>
                    <option value="rejected" selected={@business.status == :rejected}>Rejected</option>
                  </select>
                </div>
                <div class="form-control">
                  <label class="label"><span class="label-text font-medium">Rating</span></label>
                  <input type="number" step="0.1" min="0" max="5" name="business[rating]" value={@business.rating} class="input input-bordered w-full" />
                </div>
                <div class="form-control">
                  <label class="label"><span class="label-text font-medium">Speaks English</span></label>
                  <select name="business[speaks_english]" class="select select-bordered w-full">
                    <option value="">Unknown</option>
                    <option value="true" selected={@business.speaks_english == true}>Yes</option>
                    <option value="false" selected={@business.speaks_english == false}>No</option>
                  </select>
                </div>
                <div class="form-control">
                  <label class="label"><span class="label-text font-medium">Price Level</span></label>
                  <select name="business[price_level]" class="select select-bordered w-full">
                    <option value="">—</option>
                    <option value="1" selected={@business.price_level == 1}>€</option>
                    <option value="2" selected={@business.price_level == 2}>€€</option>
                    <option value="3" selected={@business.price_level == 3}>€€€</option>
                    <option value="4" selected={@business.price_level == 4}>€€€€</option>
                  </select>
                </div>
              </div>

              <div class="flex justify-end mt-4">
                <button type="submit" class="btn btn-primary" disabled={@saving}>
                  <%= if @saving do %>
                    <span class="loading loading-spinner loading-sm"></span>
                  <% else %>
                    <span class="hero-check w-5 h-5"></span>
                  <% end %>
                  Save Basic Info
                </button>
              </div>
            </div>
          </div>
        </form>

        <!-- Data Enrichment Card -->
        <div class="card bg-base-100 shadow-lg">
          <div class="card-body">
            <h2 class="card-title text-lg flex items-center gap-2">
              <span class="hero-sparkles w-5 h-5 text-primary"></span>
              Data Enrichment
            </h2>

            <div class="flex flex-col md:flex-row gap-6 mt-4">
              <%!-- Quality Score --%>
              <div class="flex flex-col items-center gap-2">
                <div class={"radial-progress text-#{quality_color(@quality_score)}"} style={"--value:#{@quality_score}; --size:5rem; --thickness:0.4rem;"} role="progressbar">
                  <span class="text-lg font-bold">{@quality_score}%</span>
                </div>
                <span class="text-xs text-base-content/60">Data Quality</span>
              </div>

              <%!-- Checklist --%>
              <div class="flex-1 grid grid-cols-2 md:grid-cols-4 gap-2">
                <%= for {label, present?} <- @quality_checklist do %>
                  <div class="flex items-center gap-1.5">
                    <%= if present? do %>
                      <span class="hero-check-circle w-4 h-4 text-success"></span>
                    <% else %>
                      <span class="hero-x-circle w-4 h-4 text-base-content/30"></span>
                    <% end %>
                    <span class={"text-sm #{if present?, do: "text-base-content", else: "text-base-content/40"}"}>{label}</span>
                  </div>
                <% end %>
              </div>
            </div>

            <%!-- Action Buttons --%>
            <div class="flex flex-wrap gap-3 mt-4 pt-4 border-t border-base-300">
              <button
                type="button"
                phx-click="search_google_places"
                class="btn btn-outline btn-sm"
                disabled={@google_places_loading || @google_places_enriching}
              >
                <%= if @google_places_loading do %>
                  <span class="loading loading-spinner loading-xs"></span>
                <% else %>
                  <span class="hero-map-pin w-4 h-4"></span>
                <% end %>
                Fetch Google Places Data
              </button>

              <%= if @business.status in [:pending, :researched] do %>
                <button
                  type="button"
                  phx-click="enrich_with_llm"
                  class="btn btn-outline btn-sm btn-secondary"
                  disabled={@saving}
                >
                  <%= if @saving do %>
                    <span class="loading loading-spinner loading-xs"></span>
                  <% else %>
                    <span class="hero-cpu-chip w-4 h-4"></span>
                  <% end %>
                  Enrich with AI
                </button>
              <% end %>

              <%= if @business.status in [:enriched, :verified] do %>
                <button
                  type="button"
                  phx-click="queue_re_enrichment"
                  class="btn btn-outline btn-sm btn-warning"
                >
                  <span class="hero-arrow-path w-4 h-4"></span>
                  Queue Re-enrichment
                </button>
              <% end %>
            </div>

            <%!-- Google Places Search Results --%>
            <%= if @google_places_results do %>
              <div class="mt-4 border border-base-300 rounded-lg overflow-hidden">
                <div class="flex items-center justify-between bg-base-200 px-4 py-2">
                  <span class="text-sm font-medium">Google Places Results</span>
                  <button type="button" phx-click="dismiss_google_places" class="btn btn-ghost btn-xs btn-circle">
                    <span class="hero-x-mark w-4 h-4"></span>
                  </button>
                </div>
                <%= if @google_places_results == [] do %>
                  <div class="px-4 py-6 text-center text-base-content/50 text-sm">
                    No results found. Try editing the business name or city.
                  </div>
                <% else %>
                  <div class="divide-y divide-base-300">
                    <%= for result <- @google_places_results do %>
                      <div class="flex items-center justify-between px-4 py-3 hover:bg-base-200/50">
                        <div class="flex-1 min-w-0">
                          <div class="font-medium text-sm truncate">{result.name}</div>
                          <div class="text-xs text-base-content/60 truncate">{result.address}</div>
                          <div class="flex items-center gap-3 mt-1 text-xs text-base-content/50">
                            <%= if result.rating do %>
                              <span>
                                <span class="text-warning">&#9733;</span> {result.rating}
                                <%= if result.review_count do %>
                                  <span class="text-base-content/40">({result.review_count})</span>
                                <% end %>
                              </span>
                            <% end %>
                            <%= if result.photos && result.photos != [] do %>
                              <span>{length(result.photos)} photos</span>
                            <% end %>
                            <%= if result.opening_hours do %>
                              <span class="text-success">Has hours</span>
                            <% end %>
                          </div>
                        </div>
                        <button
                          type="button"
                          phx-click="select_google_place"
                          phx-value-place-id={result.place_id}
                          class="btn btn-primary btn-xs ml-3"
                          disabled={@google_places_enriching}
                        >
                          <%= if @google_places_enriching do %>
                            <span class="loading loading-spinner loading-xs"></span>
                          <% else %>
                            Use This
                          <% end %>
                        </button>
                      </div>
                    <% end %>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>

        <!-- Translations Card -->
        <div class="card bg-base-100 shadow-lg">
          <div class="card-body">
            <div class="flex items-center justify-between">
              <h2 class="card-title text-lg flex items-center gap-2">
                <span class="hero-language w-5 h-5 text-primary"></span>
                Translations
              </h2>
              <%= if @active_locale != "en" do %>
                <button
                  type="button"
                  phx-click="translate_all"
                  class="btn btn-secondary btn-sm"
                  disabled={@translating != nil}
                >
                  <%= if @translating == "all" do %>
                    <span class="loading loading-spinner loading-sm"></span>
                  <% else %>
                    <span class="hero-sparkles w-4 h-4"></span>
                  <% end %>
                  Translate All from English
                </button>
              <% end %>
            </div>

            <!-- Language Tabs -->
            <div class="tabs tabs-boxed bg-base-200 p-1 mt-4">
              <%= for {code, name, flag} <- @supported_locales do %>
                <button
                  type="button"
                  phx-click="switch_locale"
                  phx-value-locale={code}
                  class={[
                    "tab gap-2",
                    if(@active_locale == code, do: "tab-active", else: "")
                  ]}
                >
                  <span>{flag}</span>
                  <span>{name}</span>
                  <%= if has_translation?(@translations_map, code) do %>
                    <span class="badge badge-success badge-xs">✓</span>
                  <% end %>
                </button>
              <% end %>
            </div>

            <!-- Translation Form -->
            <form phx-submit="save_translation" class="mt-6 space-y-4">
              <input type="hidden" name="translation[locale]" value={@active_locale} />

              <!-- Description -->
              <div class="form-control">
                <div class="flex items-center justify-between">
                  <label class="label"><span class="label-text font-medium">Description</span></label>
                  <%= if @active_locale != "en" do %>
                    <button
                      type="button"
                      phx-click="translate_field"
                      phx-value-field="description"
                      class="btn btn-ghost btn-xs"
                      disabled={@translating != nil}
                    >
                      <%= if @translating == "description" do %>
                        <span class="loading loading-spinner loading-xs"></span>
                      <% else %>
                        <span class="hero-sparkles w-3 h-3"></span> Auto-translate
                      <% end %>
                    </button>
                  <% end %>
                </div>
                <textarea
                  name="translation[description]"
                  class="textarea textarea-bordered w-full"
                  rows="3"
                  placeholder="Business description..."
                >{get_translation_field(@translations_map, @active_locale, :description)}</textarea>
              </div>

              <!-- Summary -->
              <div class="form-control">
                <div class="flex items-center justify-between">
                  <label class="label"><span class="label-text font-medium">Summary</span></label>
                  <%= if @active_locale != "en" do %>
                    <button
                      type="button"
                      phx-click="translate_field"
                      phx-value-field="summary"
                      class="btn btn-ghost btn-xs"
                      disabled={@translating != nil}
                    >
                      <%= if @translating == "summary" do %>
                        <span class="loading loading-spinner loading-xs"></span>
                      <% else %>
                        <span class="hero-sparkles w-3 h-3"></span> Auto-translate
                      <% end %>
                    </button>
                  <% end %>
                </div>
                <input
                  type="text"
                  name="translation[summary]"
                  class="input input-bordered w-full"
                  placeholder="Short one-line summary..."
                  value={get_translation_field(@translations_map, @active_locale, :summary)}
                />
              </div>

              <!-- Two columns for array fields -->
              <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                <!-- Highlights -->
                <div class="form-control">
                  <div class="flex items-center justify-between">
                    <label class="label"><span class="label-text font-medium">Highlights</span></label>
                    <%= if @active_locale != "en" do %>
                      <button
                        type="button"
                        phx-click="translate_field"
                        phx-value-field="highlights"
                        class="btn btn-ghost btn-xs"
                        disabled={@translating != nil}
                      >
                        <%= if @translating == "highlights" do %>
                          <span class="loading loading-spinner loading-xs"></span>
                        <% else %>
                          <span class="hero-sparkles w-3 h-3"></span>
                        <% end %>
                      </button>
                    <% end %>
                  </div>
                  <textarea
                    name="translation[highlights]"
                    class="textarea textarea-bordered w-full font-mono text-sm"
                    rows="4"
                    placeholder="One highlight per line..."
                  >{format_array(get_translation_field(@translations_map, @active_locale, :highlights))}</textarea>
                </div>

                <!-- Warnings -->
                <div class="form-control">
                  <div class="flex items-center justify-between">
                    <label class="label"><span class="label-text font-medium">Warnings</span></label>
                    <%= if @active_locale != "en" do %>
                      <button
                        type="button"
                        phx-click="translate_field"
                        phx-value-field="warnings"
                        class="btn btn-ghost btn-xs"
                        disabled={@translating != nil}
                      >
                        <%= if @translating == "warnings" do %>
                          <span class="loading loading-spinner loading-xs"></span>
                        <% else %>
                          <span class="hero-sparkles w-3 h-3"></span>
                        <% end %>
                      </button>
                    <% end %>
                  </div>
                  <textarea
                    name="translation[warnings]"
                    class="textarea textarea-bordered w-full font-mono text-sm"
                    rows="4"
                    placeholder="One warning per line..."
                  >{format_array(get_translation_field(@translations_map, @active_locale, :warnings))}</textarea>
                </div>

                <!-- Integration Tips -->
                <div class="form-control">
                  <div class="flex items-center justify-between">
                    <label class="label"><span class="label-text font-medium">Integration Tips</span></label>
                    <%= if @active_locale != "en" do %>
                      <button
                        type="button"
                        phx-click="translate_field"
                        phx-value-field="integration_tips"
                        class="btn btn-ghost btn-xs"
                        disabled={@translating != nil}
                      >
                        <%= if @translating == "integration_tips" do %>
                          <span class="loading loading-spinner loading-xs"></span>
                        <% else %>
                          <span class="hero-sparkles w-3 h-3"></span>
                        <% end %>
                      </button>
                    <% end %>
                  </div>
                  <textarea
                    name="translation[integration_tips]"
                    class="textarea textarea-bordered w-full font-mono text-sm"
                    rows="4"
                    placeholder="One tip per line..."
                  >{format_array(get_translation_field(@translations_map, @active_locale, :integration_tips))}</textarea>
                </div>

                <!-- Cultural Notes -->
                <div class="form-control">
                  <div class="flex items-center justify-between">
                    <label class="label"><span class="label-text font-medium">Cultural Notes</span></label>
                    <%= if @active_locale != "en" do %>
                      <button
                        type="button"
                        phx-click="translate_field"
                        phx-value-field="cultural_notes"
                        class="btn btn-ghost btn-xs"
                        disabled={@translating != nil}
                      >
                        <%= if @translating == "cultural_notes" do %>
                          <span class="loading loading-spinner loading-xs"></span>
                        <% else %>
                          <span class="hero-sparkles w-3 h-3"></span>
                        <% end %>
                      </button>
                    <% end %>
                  </div>
                  <textarea
                    name="translation[cultural_notes]"
                    class="textarea textarea-bordered w-full font-mono text-sm"
                    rows="4"
                    placeholder="One note per line..."
                  >{format_array(get_translation_field(@translations_map, @active_locale, :cultural_notes))}</textarea>
                </div>
              </div>

              <div class="flex justify-end mt-4">
                <button type="submit" class="btn btn-primary">
                  <span class="hero-check w-5 h-5"></span>
                  Save {locale_name(@active_locale)} Translation
                </button>
              </div>
            </form>
          </div>
        </div>

        <!-- Opening Hours Card -->
        <div class="card bg-base-100 shadow-lg">
          <div class="card-body">
            <h2 class="card-title text-lg flex items-center gap-2">
              <span class="hero-clock w-5 h-5 text-primary"></span>
              Opening Hours
            </h2>
            <form phx-submit="save" class="mt-4">
              <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
                <%= for day <- @days do %>
                  <div class="flex items-center gap-3">
                    <span class="w-24 text-sm font-medium">{day_label(day)}</span>
                    <input
                      type="text"
                      name={"business[opening_hours][#{day}]"}
                      value={get_day_hours(@business, day)}
                      class="input input-bordered input-sm flex-1"
                      placeholder="e.g. 9:00 - 18:00 or Closed"
                    />
                  </div>
                <% end %>
              </div>
              <div class="flex justify-end mt-4">
                <button type="submit" class="btn btn-primary btn-sm">
                  <span class="hero-check w-4 h-4"></span> Save Hours
                </button>
              </div>
            </form>
          </div>
        </div>

        <!-- Photos Card -->
        <div class="card bg-base-100 shadow-lg">
          <div class="card-body">
            <h2 class="card-title text-lg flex items-center gap-2">
              <span class="hero-photo w-5 h-5 text-primary"></span>
              Photos
            </h2>
            <%= if @business.photo_urls && @business.photo_urls != [] do %>
              <div class="flex flex-wrap gap-2 mt-4">
                <%= for url <- Enum.take(@business.photo_urls, 8) do %>
                  <img src={url} class="w-20 h-20 object-cover rounded-lg" />
                <% end %>
              </div>
            <% end %>
            <form phx-submit="save" class="mt-4">
              <textarea
                name="business[photo_urls]"
                class="textarea textarea-bordered w-full font-mono text-xs"
                rows="3"
                placeholder="One URL per line..."
              >{format_array(@business.photo_urls)}</textarea>
              <div class="flex justify-end mt-2">
                <button type="submit" class="btn btn-primary btn-sm">
                  <span class="hero-check w-4 h-4"></span> Save Photos
                </button>
              </div>
            </form>
          </div>
        </div>

        <!-- Bottom actions -->
        <div class="flex justify-between items-center pt-4">
          <.link navigate={~p"/admin/businesses"} class="btn btn-ghost">
            <span class="hero-arrow-left w-4 h-4"></span> Back to List
          </.link>
          <.link navigate={~p"/#{@region_slug}/businesses/#{@business.id}"} class="btn btn-outline">
            <span class="hero-eye w-4 h-4"></span> View Public Page
          </.link>
        </div>
      </main>
    </div>
    """
  end

  defp quality_color(score) when score >= 80, do: "success"
  defp quality_color(score) when score >= 50, do: "warning"
  defp quality_color(_score), do: "error"

  defp status_class(:pending), do: "badge-warning"
  defp status_class(:researching), do: "badge-info"
  defp status_class(:researched), do: "badge-info"
  defp status_class(:enriched), do: "badge-success"
  defp status_class(:verified), do: "badge-primary"
  defp status_class(:rejected), do: "badge-error"
  defp status_class(_), do: "badge-ghost"
end
