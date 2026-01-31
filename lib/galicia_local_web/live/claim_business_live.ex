defmodule GaliciaLocalWeb.ClaimBusinessLive do
  use GaliciaLocalWeb, :live_view

  alias GaliciaLocal.Directory.{Business, BusinessClaim}

  require Ash.Query

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Business.get_by_id(id) do
      {:ok, business} ->
        business = Ash.load!(business, [:city, :category, :owner])
        current_user = socket.assigns.current_user

        existing_claim =
          BusinessClaim
          |> Ash.Query.filter(user_id == ^current_user.id and business_id == ^business.id)
          |> Ash.read_one!()

        {:ok,
         socket
         |> assign(:page_title, gettext("Claim %{name}", name: business.name))
         |> assign(:business, business)
         |> assign(:existing_claim, existing_claim)
         |> assign(:submitted, false)
         |> assign(:message, "")}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Business not found"))
         |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("update_message", %{"message" => message}, socket) do
    {:noreply, assign(socket, :message, message)}
  end

  def handle_event("submit_claim", _params, socket) do
    business = socket.assigns.business
    current_user = socket.assigns.current_user

    case BusinessClaim
         |> Ash.Changeset.for_create(:create, %{
           business_id: business.id,
           message: socket.assigns.message
         }, actor: current_user)
         |> Ash.create() do
      {:ok, claim} ->
        {:noreply,
         socket
         |> assign(:submitted, true)
         |> assign(:existing_claim, claim)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, gettext("Could not submit claim. You may have already claimed this business."))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200">
      <div class="container mx-auto max-w-2xl px-4 py-8">
        <nav class="text-sm breadcrumbs mb-6">
          <ul>
            <li><.link navigate={~p"/"} class="hover:text-primary">{gettext("Home")}</.link></li>
            <li><.link navigate={~p"/businesses/#{@business.id}"} class="hover:text-primary">{@business.name}</.link></li>
            <li class="text-base-content/60">{gettext("Claim")}</li>
          </ul>
        </nav>

        <div class="card bg-base-100 shadow-xl">
          <div class="card-body">
            <h1 class="card-title text-2xl mb-2">
              <span class="hero-shield-check w-7 h-7 text-primary"></span>
              {gettext("Claim %{name}", name: @business.name)}
            </h1>

            <%= cond do %>
              <% @business.owner_id != nil -> %>
                <div class="alert alert-warning">
                  <span class="hero-exclamation-triangle w-5 h-5"></span>
                  <span>{gettext("This business has already been claimed by its owner.")}</span>
                </div>
                <div class="card-actions mt-4">
                  <.link navigate={~p"/businesses/#{@business.id}"} class="btn btn-ghost">
                    {gettext("Back to business")}
                  </.link>
                </div>

              <% @existing_claim != nil and not @submitted -> %>
                <div class="alert alert-info">
                  <span class="hero-information-circle w-5 h-5"></span>
                  <div>
                    <p class="font-medium">{gettext("You already submitted a claim for this business.")}</p>
                    <p class="text-sm">{gettext("Status:")} <span class="badge badge-sm">{@existing_claim.status}</span></p>
                  </div>
                </div>
                <div class="card-actions mt-4">
                  <.link navigate={~p"/businesses/#{@business.id}"} class="btn btn-ghost">
                    {gettext("Back to business")}
                  </.link>
                </div>

              <% @submitted -> %>
                <div class="alert alert-success">
                  <span class="hero-check-circle w-5 h-5"></span>
                  <div>
                    <p class="font-medium">{gettext("Claim submitted!")}</p>
                    <p class="text-sm">{gettext("We'll review your claim and get back to you. Once approved, you'll be able to manage your business listing.")}</p>
                  </div>
                </div>
                <div class="card-actions mt-4">
                  <.link navigate={~p"/businesses/#{@business.id}"} class="btn btn-primary">
                    {gettext("Back to %{name}", name: @business.name)}
                  </.link>
                </div>

              <% true -> %>
                <p class="text-base-content/70 mb-6">
                  {gettext("Are you the owner of this business? Submit a claim and our team will verify your ownership. Once approved, you'll be able to update your business information, add photos, and more.")}
                </p>

                <form phx-submit="submit_claim" class="space-y-4">
                  <div class="form-control">
                    <label class="label">
                      <span class="label-text font-medium">{gettext("Why are you the owner?")}</span>
                    </label>
                    <textarea
                      name="message"
                      phx-change="update_message"
                      placeholder={gettext("Tell us how you're connected to this business (e.g. 'I am the founder', 'I manage this location')")}
                      class="textarea textarea-bordered w-full h-32"
                      value={@message}
                    >{@message}</textarea>
                    <label class="label">
                      <span class="label-text-alt text-base-content/50">{gettext("Optional but helps us verify faster")}</span>
                    </label>
                  </div>

                  <div class="card-actions justify-end">
                    <.link navigate={~p"/businesses/#{@business.id}"} class="btn btn-ghost">
                      {gettext("Cancel")}
                    </.link>
                    <button type="submit" class="btn btn-primary">
                      <span class="hero-shield-check w-5 h-5"></span>
                      {gettext("Submit Claim")}
                    </button>
                  </div>
                </form>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
