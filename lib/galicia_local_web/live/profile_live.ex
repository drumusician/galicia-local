defmodule GaliciaLocalWeb.ProfileLive do
  use GaliciaLocalWeb, :live_view

  alias GaliciaLocal.Directory.City
  alias GaliciaLocal.Community.Review

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    cities =
      City.list!()
      |> Enum.sort_by(& &1.name)
      |> Enum.map(&{&1.name, &1.id})

    reviews =
      Review
      |> Ash.Query.for_read(:list_for_user, %{user_id: user.id}, actor: user)
      |> Ash.read!()
      |> Ash.load!([:business])

    form =
      user
      |> AshPhoenix.Form.for_update(:update_profile, as: "user", actor: user)

    {:ok,
     socket
     |> assign(:page_title, "My Profile")
     |> assign(:cities, cities)
     |> assign(:reviews, reviews)
     |> assign(:form, to_form(form))}
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    form =
      socket.assigns.form.source
      |> AshPhoenix.Form.validate(params)

    {:noreply, assign(socket, :form, to_form(form))}
  end

  def handle_event("save", %{"user" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form.source, params: params) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(:current_user, user)
         |> assign(
           :form,
           to_form(AshPhoenix.Form.for_update(user, :update_profile, as: "user", actor: user))
         )
         |> put_flash(:info, "Profile updated!")}

      {:error, form} ->
        {:noreply, assign(socket, :form, to_form(form))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-100">
      <div class="container mx-auto max-w-2xl px-4 py-8">
        <h1 class="text-3xl font-bold text-base-content mb-8">My Profile</h1>

        <div class="card bg-base-100 shadow-xl">
          <div class="card-body">
            <.form for={@form} phx-change="validate" phx-submit="save" class="space-y-4">
              <div class="form-control">
                <label class="label"><span class="label-text">Display Name</span></label>
                <input
                  type="text"
                  name={@form[:display_name].name}
                  value={@form[:display_name].value}
                  placeholder="How you want to be known"
                  class="input input-bordered w-full"
                />
              </div>

              <div class="form-control">
                <label class="label"><span class="label-text">About Me</span></label>
                <textarea
                  name={@form[:bio].name}
                  placeholder="Tell the community a bit about yourself..."
                  class="textarea textarea-bordered w-full h-24"
                >{@form[:bio].value}</textarea>
              </div>

              <div class="form-control">
                <label class="label"><span class="label-text">Where I Live</span></label>
                <select name={@form[:city_id].name} class="select select-bordered w-full">
                  <option value="">Select your area...</option>
                  <%= for {name, id} <- @cities do %>
                    <option value={id} selected={to_string(@form[:city_id].value) == to_string(id)}>
                      {name}
                    </option>
                  <% end %>
                </select>
              </div>

              <div class="form-control">
                <label class="label"><span class="label-text">Originally From</span></label>
                <input
                  type="text"
                  name={@form[:origin_country].name}
                  value={@form[:origin_country].value}
                  placeholder="e.g. Netherlands, UK, Galicia..."
                  class="input input-bordered w-full"
                />
              </div>

              <div class="form-control mt-6">
                <button type="submit" class="btn btn-primary">Save Profile</button>
              </div>
            </.form>
          </div>
        </div>

        <!-- My Reviews -->
        <%= if length(@reviews) > 0 do %>
          <h2 class="text-2xl font-bold mt-10 mb-4">My Reviews</h2>
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
