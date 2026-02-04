defmodule GaliciaLocalWeb.Admin.EditCategoryLive do
  @moduledoc """
  Admin full-page editor for categories with tabbed translations.
  Supports multiple languages with auto-translate functionality.
  """
  use GaliciaLocalWeb, :live_view

  alias GaliciaLocal.Directory.{Category, CategoryTranslation}

  @supported_locales [
    {"en", "English", "🇬🇧"},
    {"es", "Español", "🇪🇸"},
    {"nl", "Nederlands", "🇳🇱"}
  ]

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    region = socket.assigns[:current_region]
    region_slug = if region, do: region.slug, else: "galicia"

    case Category.get_by_id(id) do
      {:ok, category} ->
        category = Ash.load!(category, [:translations, :business_count])

        # Build translation map keyed by locale
        translations_map = build_translations_map(category)

        {:ok,
         socket
         |> assign(:page_title, "Edit: #{category.name}")
         |> assign(:category, category)
         |> assign(:region_slug, region_slug)
         |> assign(:supported_locales, @supported_locales)
         |> assign(:translations_map, translations_map)
         |> assign(:active_locale, "en")
         |> assign(:translating, nil)
         |> assign(:saving, false)}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, "Category not found")
         |> push_navigate(to: ~p"/admin/categories")}
    end
  end

  defp build_translations_map(category) do
    # Start with English from the category itself
    base = %{
      "en" => %{
        name: category.name,
        description: category.description,
        search_translation: category.search_translation,
        search_queries: category.search_queries || []
      }
    }

    # Add translations from the translations table
    Enum.reduce(category.translations || [], base, fn translation, acc ->
      Map.put(acc, translation.locale, %{
        name: translation.name,
        description: translation.description,
        search_translation: translation.search_translation,
        search_queries: translation.search_queries || []
      })
    end)
  end

  @impl true
  def handle_event("save", %{"category" => params}, socket) do
    socket = assign(socket, :saving, true)
    category = socket.assigns.category
    params = parse_search_queries(params)

    case Ash.update(category, params) do
      {:ok, updated} ->
        updated = Ash.load!(updated, [:translations, :business_count])

        {:noreply,
         socket
         |> assign(:category, updated)
         |> assign(:translations_map, build_translations_map(updated))
         |> assign(:saving, false)
         |> put_flash(:info, "Category updated successfully")}

      {:error, _} ->
        {:noreply,
         socket
         |> assign(:saving, false)
         |> put_flash(:error, "Failed to update category")}
    end
  end

  @impl true
  def handle_event("switch_locale", %{"locale" => locale}, socket) do
    {:noreply, assign(socket, :active_locale, locale)}
  end

  @impl true
  def handle_event("save_translation", %{"translation" => params}, socket) do
    category = socket.assigns.category
    locale = socket.assigns.active_locale
    params = parse_translation_params(params)

    # Don't save to translation table for English - that stays in the category
    if locale == "en" do
      # Update the category directly
      category_params = %{
        "name" => params.name,
        "description" => params.description,
        "search_translation" => params.search_translation,
        "search_queries" => params.search_queries
      }

      case Ash.update(category, category_params) do
        {:ok, updated} ->
          updated = Ash.load!(updated, [:translations, :business_count])
          {:noreply,
           socket
           |> assign(:category, updated)
           |> assign(:translations_map, build_translations_map(updated))
           |> put_flash(:info, "English content saved")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to save")}
      end
    else
      # Upsert to translation table
      translation_params = %{
        category_id: category.id,
        locale: locale,
        name: params.name,
        description: params.description,
        search_translation: params.search_translation,
        search_queries: params.search_queries
      }

      case CategoryTranslation.upsert(translation_params) do
        {:ok, _} ->
          # Reload category with translations
          {:ok, updated} = Category.get_by_id(category.id)
          updated = Ash.load!(updated, [:translations, :business_count])
          {:noreply,
           socket
           |> assign(:category, updated)
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
  def handle_info({:do_translate, field}, socket) do
    category = socket.assigns.category
    target_locale = socket.assigns.active_locale
    translations_map = socket.assigns.translations_map

    # Get English source
    english_content = get_in(translations_map, ["en", String.to_existing_atom(field)])

    if english_content && english_content != "" && english_content != [] do
      case translate_content(category.name, field, english_content, target_locale) do
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
    category = socket.assigns.category
    target_locale = socket.assigns.active_locale
    translations_map = socket.assigns.translations_map
    english = Map.get(translations_map, "en", %{})

    # Only translate name and description (not search queries which should be localized specifically)
    fields_to_translate = [:name, :description]
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
      case translate_all_fields(category.name, english, fields_to_translate, target_locale) do
        {:ok, translated_map} ->
          current = Map.get(translations_map, target_locale, %{})
          updated = Map.merge(current, translated_map)
          new_map = Map.put(translations_map, target_locale, updated)

          {:noreply,
           socket
           |> assign(:translations_map, new_map)
           |> assign(:translating, nil)
           |> put_flash(:info, "Fields translated to #{locale_name(target_locale)}")}

        {:error, reason} ->
          {:noreply,
           socket
           |> assign(:translating, nil)
           |> put_flash(:error, "Translation failed: #{reason}")}
      end
    end
  end

  # Translation helpers

  defp translate_content(category_name, field, content, target_locale) do
    locale_label = locale_name(target_locale)

    prompt = """
    Translate the following content from English to #{locale_label}.
    This is the "#{field}" field for a business category called "#{category_name}".

    Keep the same tone and style. For arrays, translate each item.
    Preserve any proper names or technical terms.

    Content to translate:
    #{Jason.encode!(content)}

    Respond ONLY with the translated content in the same format (string or JSON array).
    No markdown, no explanation, just the translated content.
    """

    case GaliciaLocal.AI.Claude.complete(prompt, max_tokens: 1024, model: "claude-sonnet-4-20250514") do
      {:ok, response} ->
        parse_translated_content(response, content)

      {:error, _} = error ->
        error
    end
  end

  defp translate_all_fields(category_name, english_content, fields, target_locale) do
    locale_label = locale_name(target_locale)

    content_json =
      fields
      |> Enum.map(fn field -> {Atom.to_string(field), Map.get(english_content, field)} end)
      |> Enum.into(%{})
      |> Jason.encode!()

    prompt = """
    Translate the following category content from English to #{locale_label}.
    This is for a business category called "#{category_name}".

    Keep the same tone and style. For arrays, translate each item individually.
    Preserve any proper names or technical terms.

    Content to translate:
    #{content_json}

    Respond ONLY with valid JSON containing the translated fields with the same keys.
    No markdown code blocks, just the JSON object.
    """

    case GaliciaLocal.AI.Claude.complete(prompt, max_tokens: 2048, model: "claude-sonnet-4-20250514") do
      {:ok, response} ->
        cleaned = response
          |> String.replace(~r/^```json\s*/m, "")
          |> String.replace(~r/\s*```$/m, "")
          |> String.trim()

        case Jason.decode(cleaned) do
          {:ok, data} ->
            result =
              fields
              |> Enum.reduce(%{}, fn field, acc ->
                key = Atom.to_string(field)
                case Map.get(data, key) do
                  nil -> acc
                  value -> Map.put(acc, field, value)
                end
              end)
            {:ok, result}

          {:error, _} ->
            {:error, "Invalid response format"}
        end

      {:error, _} = error ->
        error
    end
  end

  defp parse_translated_content(response, original) when is_list(original) do
    cleaned = response
      |> String.replace(~r/^```json\s*/m, "")
      |> String.replace(~r/\s*```$/m, "")
      |> String.trim()

    case Jason.decode(cleaned) do
      {:ok, list} when is_list(list) -> {:ok, list}
      _ -> {:error, "Invalid array format"}
    end
  end

  defp parse_translated_content(response, _original) do
    {:ok, String.trim(response)}
  end

  defp locale_name("en"), do: "English"
  defp locale_name("es"), do: "Spanish"
  defp locale_name("nl"), do: "Dutch"
  defp locale_name(code), do: code

  # Form parsing helpers

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

  defp parse_translation_params(params) do
    search_queries = case params["search_queries"] do
      nil -> []
      "" -> []
      text ->
        text
        |> String.split("\n")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
    end

    %{
      name: params["name"],
      description: params["description"],
      search_translation: params["search_translation"],
      search_queries: search_queries
    }
  end

  defp format_array(nil), do: ""
  defp format_array(list) when is_list(list), do: Enum.join(list, "\n")
  defp format_array(_), do: ""

  defp search_placeholder("es"), do: "e.g. abogados"
  defp search_placeholder("nl"), do: "e.g. advocaten"
  defp search_placeholder(_), do: "e.g. lawyers"

  defp has_translation?(translations_map, locale) do
    case Map.get(translations_map, locale) do
      nil -> false
      data ->
        [:name, :description]
        |> Enum.any?(fn field ->
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
    ~H"""
    <div class="min-h-screen bg-base-200">
      <!-- Sticky Header -->
      <header class="bg-base-100 border-b border-base-300 sticky top-0 z-50 shadow-sm">
        <div class="container mx-auto px-6 py-3">
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-4">
              <.link navigate={~p"/admin/categories"} class="btn btn-ghost btn-sm btn-circle">
                <span class="hero-arrow-left w-5 h-5"></span>
              </.link>
              <div class="flex items-center gap-3">
                <span class={"hero-#{@category.icon} w-8 h-8 text-primary"}></span>
                <div>
                  <h1 class="text-lg font-bold">{@category.name}</h1>
                  <p class="text-sm text-base-content/60">
                    {@category.business_count} businesses · Priority {@category.priority}
                  </p>
                </div>
              </div>
            </div>
            <div class="flex items-center gap-3">
              <.link navigate={~p"/#{@region_slug}/categories/#{@category.slug}"} class="btn btn-ghost btn-sm">
                <span class="hero-eye w-4 h-4"></span> View
              </.link>
            </div>
          </div>
        </div>
      </header>

      <main class="container mx-auto max-w-4xl px-6 py-8">
        <form phx-submit="save" class="space-y-6">
          <!-- Basic Info Card -->
          <div class="card bg-base-100 shadow-lg">
            <div class="card-body">
              <h2 class="card-title text-lg flex items-center gap-2">
                <span class="hero-cog-6-tooth w-5 h-5 text-primary"></span>
                Basic Information
              </h2>

              <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mt-4">
                <div class="form-control">
                  <label class="label"><span class="label-text font-medium">Slug</span></label>
                  <input type="text" name="category[slug]" value={@category.slug} class="input input-bordered w-full" required />
                  <label class="label"><span class="label-text-alt text-base-content/50">Used in URLs</span></label>
                </div>
                <div class="form-control">
                  <label class="label">
                    <span class="label-text font-medium">
                      Icon —
                      <a href="https://heroicons.com" target="_blank" class="link link-primary text-xs font-normal">browse heroicons.com</a>
                    </span>
                  </label>
                  <div class="flex items-center gap-3">
                    <input type="text" name="category[icon]" value={@category.icon} class="input input-bordered flex-1" placeholder="e.g. scale" />
                    <span class={"hero-#{@category.icon} w-6 h-6 text-primary"}></span>
                  </div>
                </div>
              </div>

              <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mt-2">
                <div class="form-control">
                  <label class="label"><span class="label-text font-medium">Priority</span></label>
                  <select name="category[priority]" class="select select-bordered w-full">
                    <option value="1" selected={@category.priority == 1}>1 - Expat Essentials</option>
                    <option value="2" selected={@category.priority == 2}>2 - Daily Life</option>
                    <option value="3" selected={@category.priority == 3}>3 - Lifestyle</option>
                    <option value="4" selected={@category.priority == 4}>4 - Practical</option>
                  </select>
                </div>
              </div>

              <div class="collapse collapse-arrow bg-base-200 rounded-lg mt-4">
                <input type="checkbox" />
                <div class="collapse-title font-medium text-sm">
                  AI Configuration
                </div>
                <div class="collapse-content">
                  <div class="form-control">
                    <label class="label"><span class="label-text font-medium">AI Enrichment Hints</span></label>
                    <textarea
                      name="category[enrichment_hints]"
                      class="textarea textarea-bordered w-full"
                      rows="3"
                      placeholder="Extra instructions for the AI when analyzing businesses in this category..."
                    >{@category.enrichment_hints}</textarea>
                    <label class="label"><span class="label-text-alt text-base-content/50">Guides AI analysis. Leave empty for default behavior.</span></label>
                  </div>
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
                  Translate Name & Description
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

              <!-- Name -->
              <div class="form-control">
                <div class="flex items-center justify-between">
                  <label class="label"><span class="label-text font-medium">Category Name</span></label>
                  <%= if @active_locale != "en" do %>
                    <button
                      type="button"
                      phx-click="translate_field"
                      phx-value-field="name"
                      class="btn btn-ghost btn-xs"
                      disabled={@translating != nil}
                    >
                      <%= if @translating == "name" do %>
                        <span class="loading loading-spinner loading-xs"></span>
                      <% else %>
                        <span class="hero-sparkles w-3 h-3"></span> Auto-translate
                      <% end %>
                    </button>
                  <% end %>
                </div>
                <input
                  type="text"
                  name="translation[name]"
                  class="input input-bordered w-full"
                  placeholder="Category name..."
                  value={get_translation_field(@translations_map, @active_locale, :name)}
                />
              </div>

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
                  placeholder="Category description..."
                >{get_translation_field(@translations_map, @active_locale, :description)}</textarea>
              </div>

              <div class="divider">Search Configuration</div>

              <!-- Search Translation -->
              <div class="form-control">
                <label class="label"><span class="label-text font-medium">Search Translation</span></label>
                <input
                  type="text"
                  name="translation[search_translation]"
                  class="input input-bordered w-full"
                  placeholder={search_placeholder(@active_locale)}
                  value={get_translation_field(@translations_map, @active_locale, :search_translation)}
                />
                <label class="label"><span class="label-text-alt text-base-content/50">Base search term for Google Places in this language</span></label>
              </div>

              <!-- Search Queries -->
              <div class="form-control">
                <label class="label"><span class="label-text font-medium">Search Queries</span></label>
                <textarea
                  name="translation[search_queries]"
                  class="textarea textarea-bordered w-full font-mono text-sm"
                  rows="4"
                  placeholder={"One search term per line...\nCity name will be appended automatically"}
                >{format_array(get_translation_field(@translations_map, @active_locale, :search_queries))}</textarea>
                <label class="label"><span class="label-text-alt text-base-content/50">Each line is searched separately with city name appended</span></label>
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

        <!-- Bottom actions -->
        <div class="flex justify-between items-center pt-4">
          <.link navigate={~p"/admin/categories"} class="btn btn-ghost">
            <span class="hero-arrow-left w-4 h-4"></span> Back to List
          </.link>
          <.link navigate={~p"/#{@region_slug}/categories/#{@category.slug}"} class="btn btn-outline">
            <span class="hero-eye w-4 h-4"></span> View Public Page
          </.link>
        </div>
      </main>
    </div>
    """
  end
end
