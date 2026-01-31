defmodule GaliciaLocalWeb.MemberLive do
  use GaliciaLocalWeb, :live_view

  alias GaliciaLocal.Accounts.User
  alias GaliciaLocal.Community.Review

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case User.get_by_id(%{id: id}) do
      {:ok, member} ->
        member = Ash.load!(member, [:city])

        reviews =
          Review
          |> Ash.Query.for_read(:list_for_user, %{user_id: member.id})
          |> Ash.read!()
          |> Ash.load!([:business])

        {:ok,
         socket
         |> assign(:page_title, member.display_name || gettext("Member"))
         |> assign(:member, member)
         |> assign(:reviews, reviews)}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Member not found"))
         |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-100">
      <div class="container mx-auto max-w-2xl px-4 py-8">
        <!-- Profile Header -->
        <div class="card bg-base-100 shadow-xl">
          <div class="card-body items-center text-center">
            <div class="avatar placeholder mb-4">
              <div class="bg-primary text-primary-content rounded-full w-20 h-20">
                <span class="text-3xl">
                  {String.first(@member.display_name || @member.email |> to_string())}
                </span>
              </div>
            </div>
            <h1 class="text-2xl font-bold">{@member.display_name || gettext("Community Member")}</h1>
            <%= if @member.city do %>
              <p class="text-base-content/70">
                <span class="hero-map-pin-mini w-4 h-4 inline-block"></span>
                {@member.city.name}
              </p>
            <% end %>
            <%= if @member.origin_country do %>
              <p class="text-base-content/50 text-sm">{gettext("Originally from %{country}", country: @member.origin_country)}</p>
            <% end %>
            <p class="text-base-content/50 text-sm">
              {gettext("Member since %{date}", date: Calendar.strftime(@member.inserted_at, "%B %Y"))}
            </p>
            <%= if @member.bio do %>
              <p class="text-base-content/80 mt-4 max-w-md">{@member.bio}</p>
            <% end %>
          </div>
        </div>

        <!-- Reviews -->
        <%= if length(@reviews) > 0 do %>
          <h2 class="text-xl font-bold mt-8 mb-4">
            {ngettext("1 Review", "%{count} Reviews", length(@reviews))}
          </h2>
          <div class="space-y-4">
            <%= for review <- @reviews do %>
              <div class="card bg-base-100 shadow">
                <div class="card-body py-4">
                  <div class="flex justify-between items-start">
                    <div>
                      <.link navigate={~p"/businesses/#{review.business_id}"} class="font-semibold text-primary hover:underline">
                        {review.business.name}
                      </.link>
                      <div class="flex items-center gap-1 mt-1">
                        <%= for i <- 1..5 do %>
                          <span class={if i <= review.rating, do: "text-warning", else: "text-base-content/20"}>★</span>
                        <% end %>
                      </div>
                    </div>
                    <span class="text-xs text-base-content/50">
                      {Calendar.strftime(review.inserted_at, "%b %d, %Y")}
                    </span>
                  </div>
                  <%= if review.body do %>
                    <p class="text-base-content/80 mt-2">{review.body}</p>
                  <% end %>
                  <%= if review.visited do %>
                    <span class="badge badge-success badge-sm mt-2">{gettext("Visited")}</span>
                  <% end %>
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
