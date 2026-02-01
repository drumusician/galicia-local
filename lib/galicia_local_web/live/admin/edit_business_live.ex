defmodule GaliciaLocalWeb.Admin.EditBusinessLive do
  @moduledoc """
  Admin full-page editor for business listings.
  Exposes all fields including AI-enriched data for manual refinement.
  """
  use GaliciaLocalWeb, :live_view

  alias GaliciaLocal.Directory.{Business, City, Category}

  @days ~w(monday tuesday wednesday thursday friday saturday sunday)

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Business.get_by_id(id) do
      {:ok, business} ->
        business = Ash.load!(business, [:city, :category])
        cities = City.list!() |> Enum.sort_by(& &1.name)
        categories = Category.list!() |> Enum.sort_by(& &1.name)

        {:ok,
         socket
         |> assign(:page_title, "Edit: #{business.name}")
         |> assign(:business, business)
         |> assign(:cities, cities)
         |> assign(:categories, categories)}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, "Business not found")
         |> push_navigate(to: ~p"/admin/businesses")}
    end
  end

  @impl true
  def handle_event("save", %{"business" => params}, socket) do
    business = socket.assigns.business
    params = parse_array_fields(params)
    params = parse_opening_hours(params)

    case Ash.update(business, params) do
      {:ok, updated} ->
        updated = Ash.load!(updated, [:city, :category])

        {:noreply,
         socket
         |> assign(:business, updated)
         |> put_flash(:info, "Business updated successfully")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update business")}
    end
  end

  defp parse_array_fields(params) do
    array_keys = ~w(highlights highlights_es warnings warnings_es
      integration_tips integration_tips_es cultural_notes cultural_notes_es
      service_specialties languages_taught expat_tips photo_urls)

    Enum.reduce(array_keys, params, fn key, acc ->
      case acc[key] do
        nil -> acc
        "" -> Map.put(acc, key, [])
        text when is_binary(text) ->
          items =
            text
            |> String.split("\n")
            |> Enum.map(&String.trim/1)
            |> Enum.reject(&(&1 == ""))

          Map.put(acc, key, items)

        _ -> acc
      end
    end)
  end

  defp parse_opening_hours(params) do
    hours = params["opening_hours"] || %{}

    parsed =
      Enum.reduce(@days, %{}, fn day, acc ->
        day_data = hours[day] || %{}

        if day_data["closed"] == "true" do
          Map.put(acc, day, %{"closed" => true})
        else
          open = day_data["open"]
          close = day_data["close"]

          if open in [nil, ""] and close in [nil, ""] do
            acc
          else
            Map.put(acc, day, %{"open" => open || "", "close" => close || ""})
          end
        end
      end)

    Map.put(params, "opening_hours", parsed)
  end

  defp format_array(nil), do: ""
  defp format_array(list) when is_list(list), do: Enum.join(list, "\n")
  defp format_array(_), do: ""

  defp get_hours(business, day, field) do
    case business.opening_hours do
      %{^day => %{^field => val}} -> val
      _ -> ""
    end
  end

  defp day_closed?(business, day) do
    case business.opening_hours do
      %{^day => %{"closed" => true}} -> true
      _ -> false
    end
  end

  defp day_label(day), do: String.capitalize(day)

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :days, @days)

    ~H"""
    <div class="min-h-screen bg-base-200">
      <header class="bg-base-100 border-b border-base-300 sticky top-0 z-50">
        <div class="container mx-auto px-6 py-4">
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-4">
              <.link navigate={~p"/admin/businesses"} class="btn btn-ghost btn-sm">
                <span class="hero-arrow-left w-4 h-4"></span>
              </.link>
              <div>
                <h1 class="text-xl font-bold">{@business.name}</h1>
                <p class="text-sm text-base-content/60">
                  {if @business.category, do: @business.category.name, else: "—"}
                  · {if @business.city, do: @business.city.name, else: "—"}
                </p>
              </div>
            </div>
            <div class="flex gap-2">
              <.link navigate={~p"/businesses/#{@business.id}"} class="btn btn-ghost btn-sm">
                View Public Page
              </.link>
            </div>
          </div>
        </div>
      </header>

      <main class="container mx-auto max-w-4xl px-6 py-8">
        <form phx-submit="save" class="space-y-6">
          <%!-- Basic Info --%>
          <div class="card bg-base-100 shadow">
            <div class="card-body">
              <h2 class="card-title text-lg">Basic Info</h2>
              <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mt-4">
                <div class="form-control">
                  <label class="label"><span class="label-text font-medium">Name</span></label>
                  <input type="text" name="business[name]" value={@business.name} class="input input-bordered w-full" required />
                </div>
                <div class="form-control">
                  <label class="label"><span class="label-text font-medium">Slug</span></label>
                  <input type="text" name="business[slug]" value={@business.slug} class="input input-bordered w-full" />
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
                  <label class="label"><span class="label-text font-medium">Source</span></label>
                  <input type="text" name="business[source]" value={@business.source} class="input input-bordered w-full" />
                </div>
              </div>
            </div>
          </div>

          <%!-- Contact & Location --%>
          <div class="card bg-base-100 shadow">
            <div class="card-body">
              <h2 class="card-title text-lg">Contact & Location</h2>
              <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mt-4">
                <div class="form-control md:col-span-2">
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
                <div class="form-control">
                  <label class="label"><span class="label-text font-medium">Google Maps URL</span></label>
                  <input type="url" name="business[google_maps_url]" value={@business.google_maps_url} class="input input-bordered w-full" />
                </div>
                <div class="form-control">
                  <label class="label"><span class="label-text font-medium">Latitude</span></label>
                  <input type="text" name="business[latitude]" value={@business.latitude} class="input input-bordered w-full" />
                </div>
                <div class="form-control">
                  <label class="label"><span class="label-text font-medium">Longitude</span></label>
                  <input type="text" name="business[longitude]" value={@business.longitude} class="input input-bordered w-full" />
                </div>
              </div>
            </div>
          </div>

          <%!-- Description & Summary --%>
          <div class="card bg-base-100 shadow">
            <div class="card-body">
              <h2 class="card-title text-lg">Description & Summary</h2>
              <div class="space-y-4 mt-4">
                <div class="form-control">
                  <label class="label"><span class="label-text font-medium">Description (English)</span></label>
                  <textarea name="business[description]" class="textarea textarea-bordered w-full" rows="3">{@business.description}</textarea>
                </div>
                <div class="form-control">
                  <label class="label"><span class="label-text font-medium">Descripción (Español)</span></label>
                  <textarea name="business[description_es]" class="textarea textarea-bordered w-full" rows="3">{@business.description_es}</textarea>
                </div>
                <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <div class="form-control">
                    <label class="label"><span class="label-text font-medium">Summary (English)</span></label>
                    <input type="text" name="business[summary]" value={@business.summary} class="input input-bordered w-full" />
                  </div>
                  <div class="form-control">
                    <label class="label"><span class="label-text font-medium">Resumen (Español)</span></label>
                    <input type="text" name="business[summary_es]" value={@business.summary_es} class="input input-bordered w-full" />
                  </div>
                </div>
                <div class="form-control">
                  <label class="label"><span class="label-text font-medium">Sentiment Summary</span></label>
                  <input type="text" name="business[sentiment_summary]" value={@business.sentiment_summary} class="input input-bordered w-full" />
                </div>
              </div>
            </div>
          </div>

          <%!-- AI Enrichment Data --%>
          <div class="card bg-base-100 shadow">
            <div class="card-body">
              <h2 class="card-title text-lg">AI Enrichment Data</h2>
              <p class="text-sm text-base-content/50">One item per line. Edit the AI-generated content as needed.</p>
              <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mt-4">
                <div class="form-control">
                  <label class="label"><span class="label-text font-medium">Highlights (EN)</span></label>
                  <textarea name="business[highlights]" class="textarea textarea-bordered w-full font-mono text-sm" rows="4">{format_array(@business.highlights)}</textarea>
                </div>
                <div class="form-control">
                  <label class="label"><span class="label-text font-medium">Highlights (ES)</span></label>
                  <textarea name="business[highlights_es]" class="textarea textarea-bordered w-full font-mono text-sm" rows="4">{format_array(@business.highlights_es)}</textarea>
                </div>
                <div class="form-control">
                  <label class="label"><span class="label-text font-medium">Warnings (EN)</span></label>
                  <textarea name="business[warnings]" class="textarea textarea-bordered w-full font-mono text-sm" rows="3">{format_array(@business.warnings)}</textarea>
                </div>
                <div class="form-control">
                  <label class="label"><span class="label-text font-medium">Warnings (ES)</span></label>
                  <textarea name="business[warnings_es]" class="textarea textarea-bordered w-full font-mono text-sm" rows="3">{format_array(@business.warnings_es)}</textarea>
                </div>
                <div class="form-control">
                  <label class="label"><span class="label-text font-medium">Integration Tips (EN)</span></label>
                  <textarea name="business[integration_tips]" class="textarea textarea-bordered w-full font-mono text-sm" rows="4">{format_array(@business.integration_tips)}</textarea>
                </div>
                <div class="form-control">
                  <label class="label"><span class="label-text font-medium">Integration Tips (ES)</span></label>
                  <textarea name="business[integration_tips_es]" class="textarea textarea-bordered w-full font-mono text-sm" rows="4">{format_array(@business.integration_tips_es)}</textarea>
                </div>
                <div class="form-control">
                  <label class="label"><span class="label-text font-medium">Cultural Notes (EN)</span></label>
                  <textarea name="business[cultural_notes]" class="textarea textarea-bordered w-full font-mono text-sm" rows="3">{format_array(@business.cultural_notes)}</textarea>
                </div>
                <div class="form-control">
                  <label class="label"><span class="label-text font-medium">Cultural Notes (ES)</span></label>
                  <textarea name="business[cultural_notes_es]" class="textarea textarea-bordered w-full font-mono text-sm" rows="3">{format_array(@business.cultural_notes_es)}</textarea>
                </div>
                <div class="form-control">
                  <label class="label"><span class="label-text font-medium">Service Specialties</span></label>
                  <textarea name="business[service_specialties]" class="textarea textarea-bordered w-full font-mono text-sm" rows="3">{format_array(@business.service_specialties)}</textarea>
                </div>
                <div class="form-control">
                  <label class="label"><span class="label-text font-medium">Languages Taught</span></label>
                  <textarea name="business[languages_taught]" class="textarea textarea-bordered w-full font-mono text-sm" rows="2">{format_array(@business.languages_taught)}</textarea>
                </div>
              </div>
            </div>
          </div>

          <%!-- Scores & Languages --%>
          <div class="card bg-base-100 shadow">
            <div class="card-body">
              <h2 class="card-title text-lg">Scores & Languages</h2>
              <div class="grid grid-cols-2 md:grid-cols-3 gap-4 mt-4">
                <div class="form-control">
                  <label class="label"><span class="label-text font-medium">Newcomer Friendly</span></label>
                  <input type="number" step="0.01" min="0" max="1" name="business[newcomer_friendly_score]" value={@business.newcomer_friendly_score} class="input input-bordered w-full" />
                </div>
                <div class="form-control">
                  <label class="label"><span class="label-text font-medium">Local Gem</span></label>
                  <input type="number" step="0.01" min="0" max="1" name="business[local_gem_score]" value={@business.local_gem_score} class="input input-bordered w-full" />
                </div>
                <div class="form-control">
                  <label class="label"><span class="label-text font-medium">Quality</span></label>
                  <input type="number" step="0.01" min="0" max="1" name="business[quality_score]" value={@business.quality_score} class="input input-bordered w-full" />
                </div>
                <div class="form-control">
                  <label class="label"><span class="label-text font-medium">Rating</span></label>
                  <input type="number" step="0.1" min="0" max="5" name="business[rating]" value={@business.rating} class="input input-bordered w-full" />
                </div>
                <div class="form-control">
                  <label class="label"><span class="label-text font-medium">Review Count</span></label>
                  <input type="number" name="business[review_count]" value={@business.review_count} class="input input-bordered w-full" />
                </div>
                <div class="form-control">
                  <label class="label"><span class="label-text font-medium">Price Level</span></label>
                  <input type="number" min="0" max="4" name="business[price_level]" value={@business.price_level} class="input input-bordered w-full" />
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
                  <label class="label"><span class="label-text font-medium">EN Confidence</span></label>
                  <input type="number" step="0.01" min="0" max="1" name="business[speaks_english_confidence]" value={@business.speaks_english_confidence} class="input input-bordered w-full" />
                </div>
              </div>
            </div>
          </div>

          <%!-- Opening Hours --%>
          <div class="card bg-base-100 shadow">
            <div class="card-body">
              <h2 class="card-title text-lg">Opening Hours</h2>
              <div class="space-y-2 mt-4">
                <%= for day <- @days do %>
                  <div class="flex items-center gap-3">
                    <span class="w-24 text-sm font-medium">{day_label(day)}</span>
                    <input
                      type="time"
                      name={"business[opening_hours][#{day}][open]"}
                      value={get_hours(@business, day, "open")}
                      class="input input-bordered input-sm w-32"
                    />
                    <span class="text-base-content/50">—</span>
                    <input
                      type="time"
                      name={"business[opening_hours][#{day}][close]"}
                      value={get_hours(@business, day, "close")}
                      class="input input-bordered input-sm w-32"
                    />
                    <label class="label cursor-pointer gap-2">
                      <input
                        type="checkbox"
                        name={"business[opening_hours][#{day}][closed]"}
                        value="true"
                        checked={day_closed?(@business, day)}
                        class="checkbox checkbox-sm"
                      />
                      <span class="label-text text-sm">Closed</span>
                    </label>
                  </div>
                <% end %>
              </div>
            </div>
          </div>

          <%!-- Photos --%>
          <div class="card bg-base-100 shadow">
            <div class="card-body">
              <h2 class="card-title text-lg">Photos</h2>
              <p class="text-sm text-base-content/50">One URL per line</p>
              <div class="mt-4">
                <%= if @business.photo_urls && @business.photo_urls != [] do %>
                  <div class="flex flex-wrap gap-2 mb-4">
                    <%= for url <- Enum.take(@business.photo_urls, 6) do %>
                      <img src={url} class="w-24 h-24 object-cover rounded-lg" />
                    <% end %>
                  </div>
                <% end %>
                <textarea name="business[photo_urls]" class="textarea textarea-bordered w-full font-mono text-xs" rows="4">{format_array(@business.photo_urls)}</textarea>
              </div>
            </div>
          </div>

          <%!-- Save --%>
          <div class="flex justify-end gap-3">
            <.link navigate={~p"/admin/businesses"} class="btn btn-ghost">Cancel</.link>
            <button type="submit" class="btn btn-primary">
              <span class="hero-check w-5 h-5"></span>
              Save Changes
            </button>
          </div>
        </form>
      </main>
    </div>
    """
  end
end
