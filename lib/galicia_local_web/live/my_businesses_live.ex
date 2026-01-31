defmodule GaliciaLocalWeb.MyBusinessesLive do
  use GaliciaLocalWeb, :live_view

  alias GaliciaLocal.Directory.{Business, BusinessClaim}

  require Ash.Query

  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns.current_user

    owned_businesses =
      Business
      |> Ash.Query.for_read(:owned_by, %{owner_id: current_user.id})
      |> Ash.read!()
      |> Ash.load!([:city, :category])

    pending_claims =
      BusinessClaim
      |> Ash.Query.for_read(:for_user, %{user_id: current_user.id})
      |> Ash.read!()
      |> Ash.load!([:business])

    {:ok,
     socket
     |> assign(:page_title, gettext("My Businesses"))
     |> assign(:owned_businesses, owned_businesses)
     |> assign(:pending_claims, pending_claims)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200">
      <div class="container mx-auto max-w-4xl px-4 py-8">
        <h1 class="text-3xl font-bold flex items-center gap-3 mb-8">
          <span class="hero-building-storefront w-8 h-8 text-primary"></span>
          {gettext("My Businesses")}
        </h1>

        <!-- Owned Businesses -->
        <%= if length(@owned_businesses) > 0 do %>
          <div class="space-y-4 mb-8">
            <%= for business <- @owned_businesses do %>
              <div class="card bg-base-100 shadow">
                <div class="card-body flex-row items-center justify-between">
                  <div>
                    <h3 class="font-bold text-lg">
                      <.link navigate={~p"/businesses/#{business.id}"} class="hover:text-primary">
                        {business.name}
                      </.link>
                    </h3>
                    <p class="text-sm text-base-content/60">
                      {business.category.name} · {business.city.name}
                    </p>
                  </div>
                  <.link navigate={~p"/my-businesses/#{business.id}/edit"} class="btn btn-primary btn-sm gap-1">
                    <span class="hero-pencil-square w-4 h-4"></span>
                    {gettext("Edit")}
                  </.link>
                </div>
              </div>
            <% end %>
          </div>
        <% else %>
          <div class="card bg-base-100 shadow mb-8">
            <div class="card-body text-center py-12">
              <span class="hero-building-storefront w-12 h-12 text-base-content/30 mx-auto"></span>
              <p class="text-base-content/50 mt-2">{gettext("You don't own any businesses yet.")}</p>
              <p class="text-sm text-base-content/40">{gettext("Find your business and claim it to start managing your listing.")}</p>
              <.link navigate={~p"/search"} class="btn btn-primary btn-sm mt-4">
                {gettext("Search Businesses")}
              </.link>
            </div>
          </div>
        <% end %>

        <!-- Pending Claims -->
        <%= if length(@pending_claims) > 0 do %>
          <h2 class="text-xl font-bold mb-4">{gettext("Your Claims")}</h2>
          <div class="space-y-3">
            <%= for claim <- @pending_claims do %>
              <div class="card bg-base-100 shadow">
                <div class="card-body py-4 flex-row items-center justify-between">
                  <div>
                    <.link navigate={~p"/businesses/#{claim.business.id}"} class="font-medium hover:text-primary">
                      {claim.business.name}
                    </.link>
                    <p class="text-sm text-base-content/60">
                      {gettext("Submitted %{date}", date: Calendar.strftime(claim.inserted_at, "%b %d, %Y"))}
                    </p>
                  </div>
                  <span class={[
                    "badge",
                    claim.status == :pending && "badge-warning",
                    claim.status == :approved && "badge-success",
                    claim.status == :rejected && "badge-error"
                  ]}>
                    {claim.status}
                  </span>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
