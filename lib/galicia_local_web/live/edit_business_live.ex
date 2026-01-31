defmodule GaliciaLocalWeb.EditBusinessLive do
  use GaliciaLocalWeb, :live_view

  alias GaliciaLocal.Directory.Business

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Business.get_by_id(id) do
      {:ok, business} ->
        business = Ash.load!(business, [:city, :category])
        current_user = socket.assigns.current_user

        if business.owner_id == current_user.id do
          form =
            business
            |> AshPhoenix.Form.for_update(:owner_update,
              as: "business",
              actor: current_user
            )

          {:ok,
           socket
           |> assign(:page_title, gettext("Edit %{name}", name: business.name))
           |> assign(:business, business)
           |> assign(:form, to_form(form))}
        else
          {:ok,
           socket
           |> put_flash(:error, gettext("You don't have permission to edit this business"))
           |> push_navigate(to: ~p"/my-businesses")}
        end

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Business not found"))
         |> push_navigate(to: ~p"/my-businesses")}
    end
  end

  @impl true
  def handle_event("validate", %{"business" => params}, socket) do
    form =
      socket.assigns.form.source
      |> AshPhoenix.Form.validate(params)

    {:noreply, assign(socket, :form, to_form(form))}
  end

  def handle_event("save", %{"business" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form.source, params: params) do
      {:ok, business} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Business updated successfully!"))
         |> push_navigate(to: ~p"/businesses/#{business.id}")}

      {:error, form} ->
        {:noreply, assign(socket, :form, to_form(form))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200">
      <div class="container mx-auto max-w-3xl px-4 py-8">
        <nav class="text-sm breadcrumbs mb-6">
          <ul>
            <li><.link navigate={~p"/my-businesses"} class="hover:text-primary">{gettext("My Businesses")}</.link></li>
            <li class="text-base-content/60">{@business.name}</li>
          </ul>
        </nav>

        <div class="card bg-base-100 shadow-xl">
          <div class="card-body">
            <h1 class="card-title text-2xl mb-6">
              <span class="hero-pencil-square w-7 h-7 text-primary"></span>
              {gettext("Edit %{name}", name: @business.name)}
            </h1>

            <.form for={@form} phx-change="validate" phx-submit="save" class="space-y-5">
              <fieldset class="fieldset">
                <legend class="fieldset-legend">{gettext("Business Name")}</legend>
                <input type="text" name={@form[:name].name} value={@form[:name].value} class="input input-bordered w-full" />
              </fieldset>

              <fieldset class="fieldset">
                <legend class="fieldset-legend">{gettext("Description (English)")}</legend>
                <textarea name={@form[:description].name} class="textarea textarea-bordered w-full h-32">{@form[:description].value}</textarea>
              </fieldset>

              <fieldset class="fieldset">
                <legend class="fieldset-legend">{gettext("Descripción (Español)")}</legend>
                <textarea name={@form[:description_es].name} class="textarea textarea-bordered w-full h-32">{@form[:description_es].value}</textarea>
              </fieldset>

              <fieldset class="fieldset">
                <legend class="fieldset-legend">{gettext("Short Summary")}</legend>
                <input type="text" name={@form[:summary].name} value={@form[:summary].value} class="input input-bordered w-full" />
                <p class="fieldset-label">{gettext("A brief one-liner about your business")}</p>
              </fieldset>

              <div class="divider">{gettext("Contact Information")}</div>

              <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                <fieldset class="fieldset">
                  <legend class="fieldset-legend">{gettext("Address")}</legend>
                  <input type="text" name={@form[:address].name} value={@form[:address].value} class="input input-bordered w-full" />
                </fieldset>

                <fieldset class="fieldset">
                  <legend class="fieldset-legend">{gettext("Phone")}</legend>
                  <input type="text" name={@form[:phone].name} value={@form[:phone].value} class="input input-bordered w-full" />
                </fieldset>

                <fieldset class="fieldset">
                  <legend class="fieldset-legend">{gettext("Email")}</legend>
                  <input type="email" name={@form[:email].name} value={@form[:email].value} class="input input-bordered w-full" />
                </fieldset>

                <fieldset class="fieldset">
                  <legend class="fieldset-legend">{gettext("Website")}</legend>
                  <input type="url" name={@form[:website].name} value={@form[:website].value} class="input input-bordered w-full" />
                </fieldset>
              </div>

              <div class="card-actions justify-end mt-6">
                <.link navigate={~p"/my-businesses"} class="btn btn-ghost">{gettext("Cancel")}</.link>
                <button type="submit" class="btn btn-primary">
                  <span class="hero-check w-5 h-5"></span>
                  {gettext("Save Changes")}
                </button>
              </div>
            </.form>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
