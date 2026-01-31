defmodule GaliciaLocalWeb.Admin.ClaimsLive do
  use GaliciaLocalWeb, :live_view

  alias GaliciaLocal.Directory.BusinessClaim

  require Ash.Query

  @impl true
  def mount(_params, _session, socket) do
    claims =
      BusinessClaim
      |> Ash.Query.for_read(:list_pending)
      |> Ash.read!()
      |> Ash.load!([:user, :business])

    {:ok,
     socket
     |> assign(:page_title, "Business Claims")
     |> assign(:claims, claims)}
  end

  @impl true
  def handle_event("approve", %{"id" => id}, socket) do
    claim = Enum.find(socket.assigns.claims, &(&1.id == id))

    if claim do
      # Approve the claim
      claim
      |> Ash.Changeset.for_update(:approve, %{}, actor: socket.assigns.current_user)
      |> Ash.update!()

      # Set the business owner
      claim.business
      |> Ash.Changeset.for_update(:set_owner, %{
        owner_id: claim.user_id,
        claimed_at: DateTime.utc_now()
      })
      |> Ash.update!()

      {:noreply,
       socket
       |> assign(:claims, Enum.reject(socket.assigns.claims, &(&1.id == id)))
       |> put_flash(:info, "Claim approved — #{claim.business.name} is now owned by #{claim.user.email}")}
    else
      {:noreply, socket}
    end
  end

  def handle_event("reject", %{"id" => id}, socket) do
    claim = Enum.find(socket.assigns.claims, &(&1.id == id))

    if claim do
      claim
      |> Ash.Changeset.for_update(:reject, %{}, actor: socket.assigns.current_user)
      |> Ash.update!()

      {:noreply,
       socket
       |> assign(:claims, Enum.reject(socket.assigns.claims, &(&1.id == id)))
       |> put_flash(:info, "Claim rejected")}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200">
      <div class="container mx-auto max-w-4xl px-4 py-8">
        <div class="flex items-center justify-between mb-8">
          <div>
            <h1 class="text-3xl font-bold flex items-center gap-3">
              <span class="hero-shield-check w-8 h-8 text-primary"></span>
              Business Claims
            </h1>
            <p class="text-base-content/60 mt-1">Review and approve business ownership claims.</p>
          </div>
          <.link navigate={~p"/admin"} class="btn btn-ghost btn-sm">
            ← Back to Admin
          </.link>
        </div>

        <%= if length(@claims) > 0 do %>
          <div class="space-y-4">
            <%= for claim <- @claims do %>
              <div class="card bg-base-100 shadow">
                <div class="card-body">
                  <div class="flex flex-col md:flex-row md:items-center md:justify-between gap-4">
                    <div class="flex-1">
                      <h3 class="font-bold text-lg">
                        <.link navigate={~p"/businesses/#{claim.business.id}"} class="hover:text-primary">
                          {claim.business.name}
                        </.link>
                      </h3>
                      <p class="text-sm text-base-content/60">
                        Claimed by <span class="font-medium">{claim.user.display_name || claim.user.email}</span>
                        · {Calendar.strftime(claim.inserted_at, "%b %d, %Y at %H:%M")}
                      </p>
                      <%= if claim.message do %>
                        <div class="mt-2 p-3 bg-base-200 rounded-lg text-sm">
                          <span class="font-medium">Message:</span> {claim.message}
                        </div>
                      <% end %>
                    </div>
                    <div class="flex gap-2">
                      <button phx-click="approve" phx-value-id={claim.id} class="btn btn-success btn-sm" data-confirm="Approve this claim? This will make the user the owner of this business.">
                        <span class="hero-check w-4 h-4"></span>
                        Approve
                      </button>
                      <button phx-click="reject" phx-value-id={claim.id} class="btn btn-error btn-outline btn-sm" data-confirm="Reject this claim?">
                        <span class="hero-x-mark w-4 h-4"></span>
                        Reject
                      </button>
                    </div>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        <% else %>
          <div class="card bg-base-100 shadow">
            <div class="card-body text-center py-12">
              <span class="hero-inbox w-12 h-12 text-base-content/30 mx-auto"></span>
              <p class="text-base-content/50 mt-2">No pending claims</p>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
