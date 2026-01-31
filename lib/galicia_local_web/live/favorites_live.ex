defmodule GaliciaLocalWeb.FavoritesLive do
  use GaliciaLocalWeb, :live_view

  alias GaliciaLocal.Community.Favorite

  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns.current_user

    favorites =
      Favorite
      |> Ash.Query.for_read(:list_for_user, %{user_id: current_user.id})
      |> Ash.read!()
      |> Ash.load!(business: [:city, :category])

    {:ok,
     socket
     |> assign(:page_title, gettext("My Favorites"))
     |> assign(:favorites, favorites)}
  end

  @impl true
  def handle_event("remove_favorite", %{"id" => id}, socket) do
    favorite = Enum.find(socket.assigns.favorites, &(&1.id == id))

    if favorite do
      Ash.destroy!(favorite, actor: socket.assigns.current_user)

      favorites = Enum.reject(socket.assigns.favorites, &(&1.id == id))
      {:noreply, assign(socket, :favorites, favorites)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-100">
      <div class="container mx-auto max-w-4xl px-4 py-8">
        <h1 class="text-3xl font-bold mb-2 flex items-center gap-3">
          <span class="hero-heart-solid w-8 h-8 text-error"></span>
          {gettext("My Favorites")}
        </h1>
        <p class="text-base-content/60 mb-8">{gettext("Businesses you've saved for later.")}</p>

        <%= if length(@favorites) > 0 do %>
          <div class="space-y-4">
            <%= for fav <- @favorites do %>
              <div class="card card-side bg-base-100 shadow-md hover:shadow-lg transition-shadow">
                <div class="card-body py-4">
                  <div class="flex justify-between items-start">
                    <div>
                      <.link navigate={~p"/businesses/#{fav.business.id}"} class="card-title text-lg hover:text-primary transition-colors">
                        {fav.business.name}
                      </.link>
                      <p class="text-sm text-base-content/60">
                        {localized_name(fav.business.category, @locale)} · {fav.business.city.name}
                      </p>
                      <div class="flex items-center gap-3 mt-1">
                        <%= if fav.business.rating do %>
                          <span class="text-sm">
                            <span class="text-warning">★</span>
                            {Decimal.round(fav.business.rating, 1)}
                          </span>
                        <% end %>
                        <%= if fav.business.speaks_english do %>
                          <span class="badge badge-success badge-sm gap-1">
                            <span class="hero-language w-3 h-3"></span>
                            {gettext("English")}
                          </span>
                        <% end %>
                      </div>
                    </div>
                    <button
                      phx-click="remove_favorite"
                      phx-value-id={fav.id}
                      class="btn btn-ghost btn-sm text-error"
                      data-confirm={gettext("Remove from favorites?")}
                    >
                      <span class="hero-heart-solid w-5 h-5"></span>
                    </button>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        <% else %>
          <div class="text-center py-16">
            <span class="hero-heart w-16 h-16 text-base-content/20 mx-auto mb-4"></span>
            <h3 class="text-xl font-semibold mb-2">{gettext("No favorites yet")}</h3>
            <p class="text-base-content/60 mb-6">{gettext("Browse businesses and click the heart to save them here.")}</p>
            <.link navigate={~p"/categories"} class="btn btn-primary">
              {gettext("Browse Categories")}
            </.link>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
