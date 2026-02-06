defmodule GaliciaLocalWeb.BusinessLive do
  @moduledoc """
  Business detail page showing full business information.
  """
  use GaliciaLocalWeb, :live_view

  alias GaliciaLocal.Directory.Business
  alias GaliciaLocal.Community.{Review, Favorite}
  alias GaliciaLocal.Analytics.Tracker

  require Ash.Query

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    region = socket.assigns[:current_region]
    region_slug = if region, do: region.slug, else: "galicia"

    case Business.get_by_id(id) do
      {:ok, business} ->
        business = Ash.load!(business, [:city, :category])
        if connected?(socket) and region, do: Tracker.track_async("business", business.id, region.id)
        current_user = socket.assigns[:current_user]

        reviews =
          Review
          |> Ash.Query.for_read(:list_for_business, %{business_id: business.id})
          |> Ash.read!()
          |> Ash.load!([:user])

        review_form =
          if current_user do
            AshPhoenix.Form.for_create(Review, :create,
              as: "review",
              actor: current_user
            )
          end

        is_favorited =
          if current_user do
            Favorite
            |> Ash.Query.filter(user_id == ^current_user.id and business_id == ^business.id)
            |> Ash.exists?()
          else
            false
          end

        {:ok,
         socket
         |> assign(:page_title, business.name)
         |> assign(:meta_description, business.summary || String.slice(business.description || "", 0, 160))
         |> assign(:business, business)
         |> assign(:reviews, reviews)
         |> assign(:review_form, review_form && to_form(review_form))
         |> assign(:review_rating, 5)
         |> assign(:lightbox_index, nil)
         |> assign(:is_favorited, is_favorited)
         |> assign(:region_slug, region_slug)}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Business not found"))
         |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("open_lightbox", %{"index" => idx}, socket) do
    {:noreply, assign(socket, :lightbox_index, String.to_integer(idx))}
  end

  def handle_event("close_lightbox", _params, socket) do
    {:noreply, assign(socket, :lightbox_index, nil)}
  end

  def handle_event("lightbox_keydown", %{"key" => "ArrowLeft"}, socket) do
    handle_event("lightbox_prev", %{}, socket)
  end

  def handle_event("lightbox_keydown", %{"key" => "ArrowRight"}, socket) do
    handle_event("lightbox_next", %{}, socket)
  end

  def handle_event("lightbox_keydown", %{"key" => "Escape"}, socket) do
    handle_event("close_lightbox", %{}, socket)
  end

  def handle_event("lightbox_keydown", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("lightbox_prev", _params, socket) do
    count = length(socket.assigns.business.photo_urls || [])
    idx = rem(socket.assigns.lightbox_index - 1 + count, count)
    {:noreply, assign(socket, :lightbox_index, idx)}
  end

  def handle_event("lightbox_next", _params, socket) do
    count = length(socket.assigns.business.photo_urls || [])
    idx = rem(socket.assigns.lightbox_index + 1, count)
    {:noreply, assign(socket, :lightbox_index, idx)}
  end

  def handle_event("toggle_favorite", _params, socket) do
    current_user = socket.assigns.current_user
    business = socket.assigns.business

    if socket.assigns.is_favorited do
      # Remove favorite
      Favorite
      |> Ash.Query.filter(user_id == ^current_user.id and business_id == ^business.id)
      |> Ash.read_one!()
      |> Ash.destroy!(actor: current_user)

      {:noreply, assign(socket, :is_favorited, false)}
    else
      # Add favorite
      Favorite
      |> Ash.Changeset.for_create(:create, %{business_id: business.id}, actor: current_user)
      |> Ash.create!()

      {:noreply, assign(socket, :is_favorited, true)}
    end
  end

  def handle_event("set_rating", %{"rating" => rating}, socket) do
    {:noreply, assign(socket, :review_rating, String.to_integer(rating))}
  end

  def handle_event("validate_review", %{"review" => params}, socket) do
    form =
      socket.assigns.review_form.source
      |> AshPhoenix.Form.validate(params)

    {:noreply, assign(socket, :review_form, to_form(form))}
  end

  def handle_event("submit_review", %{"review" => params}, socket) do
    params = Map.put(params, "rating", socket.assigns.review_rating)
    params = Map.put(params, "business_id", socket.assigns.business.id)

    case AshPhoenix.Form.submit(socket.assigns.review_form.source, params: params) do
      {:ok, _review} ->
        reviews =
          Review
          |> Ash.Query.for_read(:list_for_business, %{business_id: socket.assigns.business.id})
          |> Ash.read!()
          |> Ash.load!([:user])

        new_form =
          AshPhoenix.Form.for_create(Review, :create,
            as: "review",
            actor: socket.assigns.current_user
          )

        {:noreply,
         socket
         |> assign(:reviews, reviews)
         |> assign(:review_form, to_form(new_form))
         |> assign(:review_rating, 5)
         |> put_flash(:info, gettext("Review submitted!"))}

      {:error, form} ->
        {:noreply, assign(socket, :review_form, to_form(form))}
    end
  end

  def handle_event("delete_review", %{"id" => review_id}, socket) do
    review = Enum.find(socket.assigns.reviews, &(&1.id == review_id))

    if review do
      Ash.destroy!(review, actor: socket.assigns.current_user)

      reviews =
        Review
        |> Ash.Query.for_read(:list_for_business, %{business_id: socket.assigns.business.id})
        |> Ash.read!()
        |> Ash.load!([:user])

      {:noreply,
       socket
       |> assign(:reviews, reviews)
       |> put_flash(:info, gettext("Review deleted"))}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-100">
      <div class="container mx-auto max-w-4xl px-4 py-8">
        <!-- Breadcrumbs -->
        <nav class="text-sm breadcrumbs mb-6">
          <ul>
            <li><.link navigate={~p"/#{@region_slug}"} class="hover:text-primary">{gettext("Home")}</.link></li>
            <li><.link navigate={~p"/#{@region_slug}/cities/#{@business.city.slug}"} class="hover:text-primary">{@business.city.name}</.link></li>
            <li><.link navigate={~p"/#{@region_slug}/categories/#{@business.category.slug}"} class="hover:text-primary">{localized_name(@business.category, @locale)}</.link></li>
            <li class="text-base-content/60">{@business.name}</li>
          </ul>
        </nav>

        <!-- Main Card -->
        <div class="card bg-base-100 shadow-xl">
          <div class="card-body">
            <!-- Header -->
            <div class="flex flex-col md:flex-row md:justify-between md:items-start gap-4 mb-6">
              <div>
                <h1 class="text-3xl font-bold text-base-content">{@business.name}</h1>
                <p class="text-base-content/60 mt-1">
                  {@business.category.name} · {@business.city.name}
                </p>
              </div>
              <div class="flex flex-wrap gap-2 items-center">
                <%= if @current_user do %>
                  <button
                    phx-click="toggle_favorite"
                    class={"btn btn-ghost btn-sm gap-1 #{if @is_favorited, do: "text-error", else: "text-base-content/40 hover:text-error"}"}
                  >
                    <span class={if @is_favorited, do: "hero-heart-solid w-5 h-5", else: "hero-heart w-5 h-5"}></span>
                    <%= if @is_favorited, do: gettext("Saved"), else: gettext("Save") %>
                  </button>
                <% end %>
                <%= if @business.speaks_english do %>
                  <div class="badge badge-success badge-lg gap-1">
                    <span class="hero-language w-4 h-4"></span>
                    {gettext("English Spoken")}
                  </div>
                <% end %>
                <%= if @business.owner_id do %>
                  <div class="badge badge-primary badge-lg gap-1">
                    <span class="hero-shield-check w-4 h-4"></span>
                    {gettext("Claimed")}
                  </div>
                <% end %>
                <%= if @business.status == :verified do %>
                  <div class="badge badge-primary badge-lg gap-1">
                    <span class="hero-check-badge w-4 h-4"></span>
                    {gettext("Verified")}
                  </div>
                <% end %>
              </div>
            </div>

            <!-- Rating & Price -->
            <div class="flex items-center gap-6 mb-6">
              <%= if @business.rating do %>
                <div class="flex items-center gap-2">
                  <div class="flex">
                    <%= for i <- 1..5 do %>
                      <span class={if Decimal.compare(@business.rating, i) != :lt, do: "text-warning", else: "text-base-300"}>★</span>
                    <% end %>
                  </div>
                  <span class="text-lg font-bold">{Decimal.round(@business.rating, 1)}</span>
                  <span class="text-base-content/50">({ngettext("%{count} review", "%{count} reviews", @business.review_count)})</span>
                </div>
              <% end %>
              <%= if @business.price_level do %>
                <div class="text-lg">
                  <%= for i <- 1..4 do %>
                    <span class={if i <= @business.price_level, do: "text-success", else: "text-base-300"}>€</span>
                  <% end %>
                </div>
              <% end %>
            </div>

            <!-- Summary -->
            <%= if @business.summary do %>
              <div class="alert bg-primary/10 border-primary/20 mb-6">
                <span class="hero-sparkles w-5 h-5 text-primary"></span>
                <span>{localized(@business, :summary, @locale)}</span>
              </div>
            <% end %>

            <!-- Description -->
            <div class="prose max-w-none mb-8">
              <p>{localized(@business, :description, @locale)}</p>
              <%= if @business.description_es && @business.description_es != @business.description do %>
                <details class="mt-4">
                  <summary class="cursor-pointer text-sm text-base-content/60">
                    {if @locale == "es", do: gettext("View in English"), else: gettext("Ver en español")}
                  </summary>
                  <p class="mt-2 text-base-content/70 italic">
                    {if @locale == "es", do: @business.description, else: @business.description_es}
                  </p>
                </details>
              <% end %>
            </div>

            <!-- Photos -->
            <%= if length(@business.photo_urls || []) > 0 do %>
              <div class="relative group" id="photo-carousel">
                <div id="photo-scroll" class="flex gap-3 overflow-x-auto pb-2 -mx-2 px-2 mb-4 scroll-smooth scrollbar-none">
                  <%= for {url, idx} <- Enum.with_index(@business.photo_urls) do %>
                    <img
                      src={url}
                      alt={"#{@business.name} photo #{idx + 1}"}
                      class="h-32 rounded-lg object-cover flex-shrink-0 cursor-pointer hover:opacity-90 transition-opacity"
                      loading={if idx == 0, do: "eager", else: "lazy"}
                      phx-click="open_lightbox"
                      phx-value-index={idx}
                    />
                  <% end %>
                </div>
                <button
                  type="button"
                  class="absolute left-0 top-1/2 -translate-y-1/2 btn btn-circle btn-sm btn-ghost bg-base-100/80 shadow opacity-0 group-hover:opacity-100 transition-opacity"
                  onclick="document.getElementById('photo-scroll').scrollBy({left: -200, behavior: 'smooth'})"
                >
                  <span class="hero-chevron-left w-4 h-4"></span>
                </button>
                <button
                  type="button"
                  class="absolute right-0 top-1/2 -translate-y-1/2 btn btn-circle btn-sm btn-ghost bg-base-100/80 shadow opacity-0 group-hover:opacity-100 transition-opacity"
                  onclick="document.getElementById('photo-scroll').scrollBy({left: 200, behavior: 'smooth'})"
                >
                  <span class="hero-chevron-right w-4 h-4"></span>
                </button>
              </div>
            <% end %>

            <!-- Photo Lightbox -->
            <%= if @lightbox_index do %>
              <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/80" phx-click="close_lightbox">
                <div class="relative max-w-5xl w-full mx-4" phx-click-away="close_lightbox" phx-window-keydown="lightbox_keydown">
                  <img
                    src={Enum.at(@business.photo_urls, @lightbox_index)}
                    alt={"#{@business.name} photo #{@lightbox_index + 1}"}
                    class="w-full max-h-[85vh] object-contain rounded-lg"
                    onclick="event.stopPropagation()"
                  />
                  <button type="button" phx-click="close_lightbox" class="absolute -top-3 -right-3 btn btn-circle btn-sm">
                    <span class="hero-x-mark w-4 h-4"></span>
                  </button>
                  <%= if length(@business.photo_urls) > 1 do %>
                    <button type="button" phx-click="lightbox_prev" class="absolute left-2 top-1/2 -translate-y-1/2 btn btn-circle btn-ghost bg-base-100/80">
                      <span class="hero-chevron-left w-5 h-5"></span>
                    </button>
                    <button type="button" phx-click="lightbox_next" class="absolute right-2 top-1/2 -translate-y-1/2 btn btn-circle btn-ghost bg-base-100/80">
                      <span class="hero-chevron-right w-5 h-5"></span>
                    </button>
                  <% end %>
                  <div class="absolute bottom-4 left-1/2 -translate-x-1/2 badge badge-neutral">
                    {@lightbox_index + 1} / {length(@business.photo_urls)}
                  </div>
                </div>
              </div>
            <% end %>

            <!-- Highlights & Warnings -->
            <div class="grid grid-cols-1 md:grid-cols-2 gap-6 mb-8">
              <%= if length(@business.highlights || []) > 0 do %>
                <div>
                  <h3 class="font-semibold mb-3 flex items-center gap-2">
                    <span class="hero-star w-5 h-5 text-warning"></span>
                    {gettext("Highlights")}
                  </h3>
                  <ul class="space-y-2">
                    <%= for highlight <- localized(@business, :highlights, @locale) || [] do %>
                      <li class="flex items-center gap-2 text-sm">
                        <span class="hero-check w-4 h-4 text-success"></span>
                        {highlight}
                      </li>
                    <% end %>
                  </ul>
                </div>
              <% end %>

              <%= if length(@business.warnings || []) > 0 do %>
                <div>
                  <h3 class="font-semibold mb-3 flex items-center gap-2">
                    <span class="hero-exclamation-triangle w-5 h-5 text-warning"></span>
                    {gettext("Good to Know")}
                  </h3>
                  <ul class="space-y-2">
                    <%= for warning <- localized(@business, :warnings, @locale) || [] do %>
                      <li class="flex items-center gap-2 text-sm text-base-content/70">
                        <span class="hero-information-circle w-4 h-4"></span>
                        {warning}
                      </li>
                    <% end %>
                  </ul>
                </div>
              <% end %>
            </div>

            <!-- Contact Information -->
            <div class="divider">{gettext("Contact Information")}</div>
            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
              <%= if @business.address do %>
                <div class="flex items-start gap-3">
                  <span class="hero-map-pin w-5 h-5 text-primary mt-0.5"></span>
                  <div>
                    <p class="font-medium">{gettext("Address")}</p>
                    <p class="text-base-content/70">{@business.address}</p>
                  </div>
                </div>
              <% end %>

              <%= if @business.phone do %>
                <div class="flex items-start gap-3">
                  <span class="hero-phone w-5 h-5 text-primary mt-0.5"></span>
                  <div>
                    <p class="font-medium">{gettext("Phone")}</p>
                    <a href={"tel:#{@business.phone}"} class="text-primary hover:underline">
                      {@business.phone}
                    </a>
                  </div>
                </div>
              <% end %>

              <%= if @business.email do %>
                <div class="flex items-start gap-3">
                  <span class="hero-envelope w-5 h-5 text-primary mt-0.5"></span>
                  <div>
                    <p class="font-medium">{gettext("Email")}</p>
                    <a href={"mailto:#{@business.email}"} class="text-primary hover:underline">
                      {@business.email}
                    </a>
                  </div>
                </div>
              <% end %>

              <%= if @business.website do %>
                <div class="flex items-start gap-3">
                  <span class="hero-globe-alt w-5 h-5 text-primary mt-0.5"></span>
                  <div>
                    <p class="font-medium">{gettext("Website")}</p>
                    <a href={@business.website} target="_blank" rel="nofollow noopener noreferrer" class="text-primary hover:underline">
                      {URI.parse(@business.website).host || @business.website}
                    </a>
                  </div>
                </div>
              <% end %>
            </div>

            <!-- Opening Hours -->
            <%= if @business.opening_hours && map_size(@business.opening_hours) > 0 do %>
              <div class="mt-6">
                <h3 class="font-semibold mb-3 flex items-center gap-2">
                  <span class="hero-clock w-5 h-5 text-primary"></span>
                  {gettext("Opening Hours")}
                </h3>
                <div class="grid grid-cols-1 gap-1 text-sm">
                  <%= for day <- ~w(monday tuesday wednesday thursday friday saturday sunday) do %>
                    <% hours_text = @business.opening_hours[day] %>
                    <%= if hours_text do %>
                      <% short_hours = String.replace(hours_text, ~r/^[A-Za-z]+:\s*/, "") %>
                      <div class={[
                        "flex justify-between py-1 px-2 rounded",
                        if(current_day() == day, do: "bg-primary/10 font-medium", else: "")
                      ]}>
                        <span class="capitalize">{day}</span>
                        <span class={if short_hours == "Closed", do: "text-base-content/40", else: ""}>{short_hours}</span>
                      </div>
                    <% end %>
                  <% end %>
                </div>
              </div>
            <% end %>

            <!-- Languages -->
            <%= if length(@business.languages_spoken || []) > 0 do %>
              <div class="mt-6">
                <h3 class="font-semibold mb-3 flex items-center gap-2">
                  <span class="hero-language w-5 h-5 text-primary"></span>
                  {gettext("Languages Spoken")}
                </h3>
                <div class="flex flex-wrap gap-2">
                  <%= for lang <- @business.languages_spoken do %>
                    <span class={"badge #{if lang == :en, do: "badge-success", else: "badge-outline"}"}>
                      {language_name(lang)}
                    </span>
                  <% end %>
                </div>
                <%= if @business.speaks_english && @business.speaks_english_confidence do %>
                  <p class="text-xs text-base-content/50 mt-2">
                    {gettext("English confidence:")} {trunc(Decimal.to_float(@business.speaks_english_confidence) * 100)}%
                  </p>
                <% end %>
              </div>
            <% end %>

            <!-- Languages Taught (for language schools) -->
            <%= if length(@business.languages_taught || []) > 0 do %>
              <div class="mt-6">
                <h3 class="font-semibold mb-3 flex items-center gap-2">
                  <span class="hero-academic-cap w-5 h-5 text-primary"></span>
                  {gettext("Languages Taught")}
                </h3>
                <div class="flex flex-wrap gap-2">
                  <%= for lang <- @business.languages_taught do %>
                    <span class="badge badge-primary badge-outline">{lang}</span>
                  <% end %>
                </div>
              </div>
            <% end %>

            <!-- Map Placeholder -->
            <%= if @business.latitude && @business.longitude do %>
              <div class="divider">{gettext("Location")}</div>
              <div
                id="map"
                class="h-64 bg-base-200 rounded-lg flex items-center justify-center"
                data-lat={Decimal.to_string(@business.latitude)}
                data-lng={Decimal.to_string(@business.longitude)}
                data-name={@business.name}
                phx-hook="LeafletMap"
              >
                <div class="text-center text-base-content/50">
                  <span class="hero-map w-12 h-12 mb-2"></span>
                  <p>{gettext("Loading map...")}</p>
                </div>
              </div>
            <% end %>

            <!-- Claim Business -->
            <%= if is_nil(@business.owner_id) and @current_user do %>
              <div class="divider"></div>
              <div class="flex items-center justify-between bg-base-200 rounded-lg p-4">
                <div>
                  <p class="font-medium">{gettext("Is this your business?")}</p>
                  <p class="text-sm text-base-content/60">{gettext("Claim it to update your information and manage your listing.")}</p>
                </div>
                <.link navigate={~p"/#{@region_slug}/businesses/#{@business.id}/claim"} class="btn btn-outline btn-sm gap-1">
                  <span class="hero-shield-check w-4 h-4"></span>
                  {gettext("Claim")}
                </.link>
              </div>
            <% end %>

            <!-- External Links -->
            <div class="card-actions justify-end mt-8">
              <%= if @business.google_maps_url do %>
                <a href={@business.google_maps_url} target="_blank" rel="noopener noreferrer" class="btn btn-outline">
                  <span class="hero-map w-5 h-5"></span>
                  {gettext("View on Google Maps")}
                </a>
              <% end %>
              <%= if @business.latitude && @business.longitude do %>
                <a
                  href={"https://www.google.com/maps/dir/?api=1&destination=#{@business.latitude},#{@business.longitude}"}
                  target="_blank"
                  rel="noopener noreferrer"
                  class="btn btn-primary"
                >
                  <span class="hero-arrow-top-right-on-square w-5 h-5"></span>
                  {gettext("Get Directions")}
                </a>
              <% end %>
            </div>
          </div>
        </div>

        <!-- Community Reviews -->
        <div class="mt-8">
          <h2 class="text-2xl font-bold mb-6 flex items-center gap-2">
            <span class="hero-chat-bubble-left-right w-6 h-6 text-primary"></span>
            {gettext("Community Reviews")} ({length(@reviews)})
          </h2>

          <!-- Review Form -->
          <%= if @review_form do %>
            <div class="card bg-base-100 shadow-xl mb-6">
              <div class="card-body">
                <h3 class="font-semibold mb-3">{gettext("Share your experience")}</h3>
                <.form for={@review_form} phx-change="validate_review" phx-submit="submit_review" class="space-y-4">
                  <div class="flex items-center gap-1">
                    <span class="text-sm mr-2">{gettext("Rating:")}</span>
                    <%= for i <- 1..5 do %>
                      <button
                        type="button"
                        phx-click="set_rating"
                        phx-value-rating={i}
                        class={"text-2xl cursor-pointer transition-colors #{if i <= @review_rating, do: "text-warning", else: "text-base-content/20 hover:text-warning/50"}"}
                      >★</button>
                    <% end %>
                  </div>

                  <div class="form-control">
                    <textarea
                      name={@review_form[:body].name}
                      placeholder={gettext("What was your experience like? Any tips for others?")}
                      class="textarea textarea-bordered w-full h-24"
                    >{@review_form[:body].value}</textarea>
                  </div>

                  <div class="flex items-center gap-4">
                    <label class="label cursor-pointer gap-2">
                      <input type="checkbox" name={@review_form[:visited].name} value="true" class="checkbox checkbox-sm" />
                      <span class="label-text">{gettext("I have visited this place")}</span>
                    </label>
                  </div>

                  <button type="submit" class="btn btn-primary btn-sm">{gettext("Submit Review")}</button>
                </.form>
              </div>
            </div>
          <% else %>
            <div class="alert mb-6">
              <span class="hero-information-circle w-5 h-5"></span>
              <span><.link navigate={~p"/sign-in"} class="text-primary font-semibold hover:underline">{gettext("Sign in")}</.link> {gettext("to leave a review")}</span>
            </div>
          <% end %>

          <!-- Reviews List -->
          <%= if length(@reviews) > 0 do %>
            <div class="space-y-4">
              <%= for review <- @reviews do %>
                <div class="card bg-base-100 shadow">
                  <div class="card-body py-4">
                    <div class="flex justify-between items-start">
                      <div class="flex items-center gap-3">
                        <div class="avatar placeholder">
                          <div class="bg-neutral text-neutral-content rounded-full w-10 h-10">
                            <span class="text-sm">
                              {String.first(review.user.display_name || review.user.email |> to_string())}
                            </span>
                          </div>
                        </div>
                        <div>
                          <.link navigate={~p"/#{@region_slug}/members/#{review.user_id}"} class="font-semibold hover:text-primary">
                            {review.user.display_name || gettext("Community Member")}
                          </.link>
                          <div class="flex items-center gap-1">
                            <%= for i <- 1..5 do %>
                              <span class={"text-sm #{if i <= review.rating, do: "text-warning", else: "text-base-content/20"}"}>★</span>
                            <% end %>
                            <%= if review.visited do %>
                              <span class="badge badge-success badge-xs ml-2">{gettext("Visited")}</span>
                            <% end %>
                          </div>
                        </div>
                      </div>
                      <div class="flex items-center gap-2">
                        <span class="text-xs text-base-content/50">
                          {Calendar.strftime(review.inserted_at, "%b %d, %Y")}
                        </span>
                        <%= if @current_user && @current_user.id == review.user_id do %>
                          <button phx-click="delete_review" phx-value-id={review.id} data-confirm={gettext("Delete this review?")} class="btn btn-ghost btn-xs text-error">
                            <span class="hero-trash w-4 h-4"></span>
                          </button>
                        <% end %>
                      </div>
                    </div>
                    <%= if review.body do %>
                      <p class="text-base-content/80 mt-2">{review.body}</p>
                    <% end %>
                  </div>
                </div>
              <% end %>
            </div>
          <% else %>
            <p class="text-base-content/50 text-center py-8">{gettext("No reviews yet. Be the first to share your experience!")}</p>
          <% end %>
        </div>

        <!-- Back link -->
        <div class="mt-8 text-center">
          <.link navigate={~p"/#{@region_slug}/cities/#{@business.city.slug}"} class="btn btn-ghost">
            {gettext("Back to %{city}", city: @business.city.name)}
          </.link>
        </div>
      </div>
    </div>
    """
  end

  defp current_day do
    case Date.day_of_week(Date.utc_today()) do
      1 -> "monday"
      2 -> "tuesday"
      3 -> "wednesday"
      4 -> "thursday"
      5 -> "friday"
      6 -> "saturday"
      7 -> "sunday"
    end
  end

  defp language_name(:es), do: gettext("Spanish")
  defp language_name(:en), do: gettext("English")
  defp language_name(:gl), do: gettext("Galician")
  defp language_name(:pt), do: gettext("Portuguese")
  defp language_name(:de), do: gettext("German")
  defp language_name(:fr), do: gettext("French")
  defp language_name(:nl), do: gettext("Dutch")
  defp language_name(lang), do: to_string(lang)
end
