defmodule GaliciaLocalWeb.Admin.SuggestionsLive do
  use GaliciaLocalWeb, :live_view

  alias GaliciaLocal.Community.Suggestion
  alias GaliciaLocal.Directory.{Business, City, Category}

  require Ash.Query

  @impl true
  def mount(_params, _session, socket) do
    region = socket.assigns[:current_region]
    region_slug = if region, do: region.slug, else: "galicia"

    cities =
      City
      |> then(fn q -> if region, do: Ash.Query.set_tenant(q, region.id), else: q end)
      |> Ash.read!()
      |> Enum.sort_by(& &1.name)

    categories = Category.list!() |> Enum.sort_by(& &1.name)

    suggestions =
      Suggestion.list_all!(actor: socket.assigns.current_user)
      |> Ash.load!([:user, :category])

    {:ok,
     socket
     |> assign(:page_title, gettext("Suggestions"))
     |> assign(:region_slug, region_slug)
     |> assign(:suggestions, suggestions)
     |> assign(:cities, cities)
     |> assign(:categories, categories)
     |> assign(:filter_status, "pending")
     |> assign(:approving_id, nil)}
  end

  @impl true
  def handle_event("filter", %{"status" => status}, socket) do
    {:noreply, assign(socket, :filter_status, status)}
  end

  def handle_event("start_approve", %{"id" => id}, socket) do
    suggestion = find_suggestion(socket, id)

    # Try to auto-match city by name
    matched_city =
      Enum.find(socket.assigns.cities, fn city ->
        String.downcase(city.name) == String.downcase(suggestion.city_name || "")
      end)

    {:noreply,
     socket
     |> assign(:approving_id, id)
     |> assign(:approve_city_id, matched_city && matched_city.id)
     |> assign(:approve_category_id, suggestion.category_id)}
  end

  def handle_event("cancel_approve", _, socket) do
    {:noreply, assign(socket, :approving_id, nil)}
  end

  def handle_event("approve", %{"suggestion_id" => id, "city_id" => city_id, "category_id" => category_id}, socket) do
    suggestion = find_suggestion(socket, id)
    region = socket.assigns.current_region

    if suggestion && region && city_id != "" do
      # Create business from suggestion
      slug = Slug.slugify(suggestion.business_name || "business")

      attrs = %{
        name: suggestion.business_name,
        slug: slug,
        city_id: city_id,
        category_id: if(category_id != "", do: category_id, else: nil),
        region_id: region.id,
        address: suggestion.address,
        website: suggestion.website,
        phone: suggestion.phone,
        status: :pending,
        source: :user_submitted
      }

      case Business
           |> Ash.Changeset.for_create(:create, attrs)
           |> Ash.create() do
        {:ok, business} ->
          # Mark suggestion as approved
          suggestion
          |> Ash.Changeset.for_update(:update_status, %{status: :approved},
            actor: socket.assigns.current_user
          )
          |> Ash.update!()

          suggestions =
            update_suggestion_status(socket.assigns.suggestions, id, :approved)

          {:noreply,
           socket
           |> assign(:suggestions, suggestions)
           |> assign(:approving_id, nil)
           |> put_flash(
             :info,
             gettext("Approved! Business \"%{name}\" created and queued for enrichment.",
               name: business.name
             )
           )}

        {:error, changeset} ->
          {:noreply,
           socket
           |> put_flash(:error, gettext("Failed to create business: %{error}",
             error: inspect(changeset.errors)
           ))}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Please select a city."))}
    end
  end

  def handle_event("dismiss", %{"id" => id}, socket) do
    suggestion = find_suggestion(socket, id)

    if suggestion do
      suggestion
      |> Ash.Changeset.for_update(:update_status, %{status: :dismissed},
        actor: socket.assigns.current_user
      )
      |> Ash.update!()

      suggestions =
        update_suggestion_status(socket.assigns.suggestions, id, :dismissed)

      {:noreply,
       socket
       |> assign(:suggestions, suggestions)
       |> put_flash(:info, gettext("Suggestion dismissed."))}
    else
      {:noreply, socket}
    end
  end

  defp find_suggestion(socket, id) do
    Enum.find(socket.assigns.suggestions, &(&1.id == id))
  end

  defp update_suggestion_status(suggestions, id, new_status) do
    Enum.map(suggestions, fn s ->
      if s.id == id, do: %{s | status: new_status}, else: s
    end)
  end

  defp filtered_suggestions(suggestions, "all"), do: suggestions

  defp filtered_suggestions(suggestions, status) do
    status_atom = String.to_existing_atom(status)
    Enum.filter(suggestions, &(&1.status == status_atom))
  end

  defp status_badge_class(:pending), do: "badge-warning"
  defp status_badge_class(:approved), do: "badge-success"
  defp status_badge_class(:dismissed), do: "badge-ghost"

  defp count_by_status(suggestions, status) do
    Enum.count(suggestions, &(&1.status == status))
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :filtered, filtered_suggestions(assigns.suggestions, assigns.filter_status))

    ~H"""
    <div class="min-h-screen bg-base-200">
      <div class="container mx-auto max-w-4xl px-4 py-8">
        <div class="flex items-center justify-between mb-8">
          <div>
            <h1 class="text-3xl font-bold flex items-center gap-3">
              <span class="hero-light-bulb w-8 h-8 text-primary"></span>
              {gettext("Suggestions")}
            </h1>
            <p class="text-base-content/60 mt-1">{gettext("Review user-submitted business recommendations.")}</p>
          </div>
          <.link navigate={~p"/admin"} class="btn btn-ghost btn-sm">
            {gettext("Back to Admin")}
          </.link>
        </div>

        <!-- Status filter tabs -->
        <div class="tabs tabs-boxed mb-6">
          <button
            phx-click="filter"
            phx-value-status="pending"
            class={"tab #{if @filter_status == "pending", do: "tab-active"}"}
          >
            {gettext("Pending")}
            <span class="badge badge-warning badge-sm ml-1">{count_by_status(@suggestions, :pending)}</span>
          </button>
          <button
            phx-click="filter"
            phx-value-status="approved"
            class={"tab #{if @filter_status == "approved", do: "tab-active"}"}
          >
            {gettext("Approved")}
            <span class="badge badge-success badge-sm ml-1">{count_by_status(@suggestions, :approved)}</span>
          </button>
          <button
            phx-click="filter"
            phx-value-status="dismissed"
            class={"tab #{if @filter_status == "dismissed", do: "tab-active"}"}
          >
            {gettext("Dismissed")}
            <span class="badge badge-ghost badge-sm ml-1">{count_by_status(@suggestions, :dismissed)}</span>
          </button>
          <button
            phx-click="filter"
            phx-value-status="all"
            class={"tab #{if @filter_status == "all", do: "tab-active"}"}
          >
            {gettext("All")}
            <span class="badge badge-sm ml-1">{length(@suggestions)}</span>
          </button>
        </div>

        <%= if length(@filtered) > 0 do %>
          <div class="space-y-4">
            <%= for suggestion <- @filtered do %>
              <div class="card bg-base-100 shadow">
                <div class="card-body">
                  <div class="flex flex-col gap-4">
                    <!-- Header row -->
                    <div class="flex items-start justify-between">
                      <div>
                        <h3 class="font-bold text-lg">{suggestion.business_name}</h3>
                        <p class="text-sm text-base-content/60">
                          <span class="hero-map-pin w-3 h-3 inline"></span>
                          {suggestion.city_name}
                          <%= if suggestion.category do %>
                            · <span class="badge badge-sm">{suggestion.category.name}</span>
                          <% end %>
                        </p>
                      </div>
                      <span class={"badge #{status_badge_class(suggestion.status)}"}>{suggestion.status}</span>
                    </div>

                    <!-- Details -->
                    <div class="grid grid-cols-1 md:grid-cols-2 gap-2 text-sm">
                      <%= if suggestion.address do %>
                        <div><span class="font-medium">{gettext("Address")}:</span> {suggestion.address}</div>
                      <% end %>
                      <%= if suggestion.website do %>
                        <div>
                          <span class="font-medium">{gettext("Website")}:</span>
                          <a href={suggestion.website} target="_blank" class="link link-primary">{suggestion.website}</a>
                        </div>
                      <% end %>
                      <%= if suggestion.phone do %>
                        <div><span class="font-medium">{gettext("Phone")}:</span> {suggestion.phone}</div>
                      <% end %>
                    </div>

                    <%= if suggestion.reason do %>
                      <div class="p-3 bg-base-200 rounded-lg text-sm">
                        <span class="font-medium">{gettext("Why recommended")}:</span> {suggestion.reason}
                      </div>
                    <% end %>

                    <!-- Meta -->
                    <div class="text-xs text-base-content/50">
                      {gettext("Submitted by")} <span class="font-medium">{suggestion.user.display_name || suggestion.user.email}</span>
                      · {Calendar.strftime(suggestion.inserted_at, "%b %d, %Y at %H:%M")}
                    </div>

                    <!-- Approve form (inline, shown when approving this suggestion) -->
                    <%= if @approving_id == suggestion.id do %>
                      <div class="border border-primary/20 rounded-lg p-4 bg-primary/5">
                        <h4 class="font-medium mb-3">{gettext("Create business from this suggestion")}</h4>
                        <form phx-submit="approve" class="flex flex-col gap-3">
                          <input type="hidden" name="suggestion_id" value={suggestion.id} />
                          <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
                            <div class="form-control">
                              <label class="label py-1"><span class="label-text text-sm">{gettext("City")} *</span></label>
                              <select name="city_id" class="select select-bordered select-sm w-full" required>
                                <option value="">{gettext("Select city...")}</option>
                                <%= for city <- @cities do %>
                                  <option value={city.id} selected={city.id == @approve_city_id}>{city.name}</option>
                                <% end %>
                              </select>
                            </div>
                            <div class="form-control">
                              <label class="label py-1"><span class="label-text text-sm">{gettext("Category")}</span></label>
                              <select name="category_id" class="select select-bordered select-sm w-full">
                                <option value="">{gettext("No category")}</option>
                                <%= for cat <- @categories do %>
                                  <option value={cat.id} selected={cat.id == @approve_category_id}>{cat.name}</option>
                                <% end %>
                              </select>
                            </div>
                          </div>
                          <div class="flex gap-2 justify-end">
                            <button type="button" phx-click="cancel_approve" class="btn btn-ghost btn-sm">{gettext("Cancel")}</button>
                            <button type="submit" class="btn btn-success btn-sm">
                              <span class="hero-check w-4 h-4"></span>
                              {gettext("Create Business")}
                            </button>
                          </div>
                        </form>
                      </div>
                    <% end %>

                    <!-- Action buttons (only for pending) -->
                    <%= if suggestion.status == :pending && @approving_id != suggestion.id do %>
                      <div class="flex gap-2 justify-end">
                        <button phx-click="start_approve" phx-value-id={suggestion.id} class="btn btn-success btn-sm">
                          <span class="hero-check w-4 h-4"></span>
                          {gettext("Approve")}
                        </button>
                        <button
                          phx-click="dismiss"
                          phx-value-id={suggestion.id}
                          class="btn btn-ghost btn-sm"
                          data-confirm={gettext("Dismiss this suggestion?")}
                        >
                          <span class="hero-x-mark w-4 h-4"></span>
                          {gettext("Dismiss")}
                        </button>
                      </div>
                    <% end %>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        <% else %>
          <div class="card bg-base-100 shadow">
            <div class="card-body text-center py-12">
              <span class="hero-inbox w-12 h-12 text-base-content/30 mx-auto"></span>
              <p class="text-base-content/50 mt-2">{gettext("No suggestions found.")}</p>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
