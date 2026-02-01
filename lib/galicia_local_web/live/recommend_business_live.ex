defmodule GaliciaLocalWeb.RecommendBusinessLive do
  @moduledoc """
  A simple form for users to recommend a business to add to the directory.
  """
  use GaliciaLocalWeb, :live_view

  alias GaliciaLocal.Directory.Category
  alias GaliciaLocal.Community.Suggestion

  @impl true
  def mount(_params, _session, socket) do
    categories = Category.list!() |> Enum.sort_by(& &1.priority)

    {:ok,
     socket
     |> assign(:page_title, gettext("Recommend a Place"))
     |> assign(:categories, categories)
     |> assign(:submitted, false)
     |> assign_form()}
  end

  defp assign_form(socket) do
    form =
      Suggestion
      |> AshPhoenix.Form.for_create(:create,
        actor: socket.assigns.current_user,
        forms: [auto?: true]
      )
      |> to_form()

    assign(socket, :form, form)
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    form =
      socket.assigns.form.source
      |> AshPhoenix.Form.validate(params)
      |> to_form()

    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("submit", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form.source, params: params) do
      {:ok, _suggestion} ->
        {:noreply,
         socket
         |> assign(:submitted, true)
         |> put_flash(:info, gettext("Thanks for your recommendation! We'll review it soon."))}

      {:error, form} ->
        {:noreply, assign(socket, :form, to_form(form))}
    end
  end

  def handle_event("recommend_another", _, socket) do
    {:noreply,
     socket
     |> assign(:submitted, false)
     |> assign_form()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200">
      <div class="container mx-auto max-w-2xl px-4 py-8">
        <nav class="text-sm breadcrumbs mb-6">
          <ul>
            <li><.link navigate={~p"/"} class="hover:text-primary">{gettext("Home")}</.link></li>
            <li class="text-base-content/60">{gettext("Recommend a Place")}</li>
          </ul>
        </nav>

        <%= if @submitted do %>
          <div class="card bg-base-100 shadow-xl">
            <div class="card-body text-center py-16">
              <div class="flex justify-center mb-4">
                <div class="bg-success/10 rounded-full p-4">
                  <span class="hero-check-circle w-12 h-12 text-success"></span>
                </div>
              </div>
              <h2 class="text-2xl font-bold">{gettext("Thank you!")}</h2>
              <p class="text-base-content/70 mt-2 max-w-md mx-auto">
                {gettext("Your recommendation has been submitted. We'll review it and add it to the directory if it's a good fit.")}
              </p>
              <div class="flex justify-center gap-3 mt-8">
                <button phx-click="recommend_another" class="btn btn-primary">
                  <span class="hero-plus w-4 h-4"></span>
                  {gettext("Recommend Another")}
                </button>
                <.link navigate={~p"/"} class="btn btn-ghost">{gettext("Back to Home")}</.link>
              </div>
            </div>
          </div>
        <% else %>
          <div class="card bg-base-100 shadow-xl">
            <div class="card-body">
              <h1 class="card-title text-2xl mb-1">
                <span class="hero-light-bulb w-7 h-7 text-primary"></span>
                {gettext("Recommend a Place")}
              </h1>
              <p class="text-base-content/60 mb-6">
                {gettext("Know a great local business in Galicia? Help the community by recommending it!")}
              </p>

              <.form for={@form} phx-change="validate" phx-submit="submit" class="space-y-5">
                <div class="form-control">
                  <label class="label">
                    <span class="label-text font-medium">{gettext("Business Name")} <span class="text-error">*</span></span>
                  </label>
                  <input
                    type="text"
                    name={@form[:business_name].name}
                    value={@form[:business_name].value}
                    class={"input input-bordered w-full #{if @form[:business_name].errors != [], do: "input-error"}"}
                    placeholder={gettext("e.g. Café La Marina")}
                    required
                  />
                  <%= for error <- @form[:business_name].errors do %>
                    <label class="label"><span class="label-text-alt text-error">{translate_error(error)}</span></label>
                  <% end %>
                </div>

                <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <div class="form-control">
                    <label class="label">
                      <span class="label-text font-medium">{gettext("City / Town")} <span class="text-error">*</span></span>
                    </label>
                    <input
                      type="text"
                      name={@form[:city_name].name}
                      value={@form[:city_name].value}
                      class={"input input-bordered w-full #{if @form[:city_name].errors != [], do: "input-error"}"}
                      placeholder={gettext("e.g. Vigo, Ourense, Pontevedra")}
                      required
                    />
                    <%= for error <- @form[:city_name].errors do %>
                      <label class="label"><span class="label-text-alt text-error">{translate_error(error)}</span></label>
                    <% end %>
                  </div>

                  <div class="form-control">
                    <label class="label">
                      <span class="label-text font-medium">{gettext("Category")}</span>
                    </label>
                    <select
                      name={@form[:category_id].name}
                      class="select select-bordered w-full"
                    >
                      <option value="">{gettext("Select a category...")}</option>
                      <%= for category <- @categories do %>
                        <option value={category.id} selected={to_string(@form[:category_id].value) == to_string(category.id)}>
                          {localized_name(category, @locale)}
                        </option>
                      <% end %>
                    </select>
                  </div>
                </div>

                <div class="form-control">
                  <label class="label">
                    <span class="label-text font-medium">{gettext("Address")}</span>
                  </label>
                  <input
                    type="text"
                    name={@form[:address].name}
                    value={@form[:address].value}
                    class="input input-bordered w-full"
                    placeholder={gettext("e.g. Rúa do Franco 12, Santiago de Compostela")}
                  />
                </div>

                <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <div class="form-control">
                    <label class="label">
                      <span class="label-text font-medium">{gettext("Website")}</span>
                    </label>
                    <input
                      type="url"
                      name={@form[:website].name}
                      value={@form[:website].value}
                      class="input input-bordered w-full"
                      placeholder="https://..."
                    />
                  </div>

                  <div class="form-control">
                    <label class="label">
                      <span class="label-text font-medium">{gettext("Phone")}</span>
                    </label>
                    <input
                      type="tel"
                      name={@form[:phone].name}
                      value={@form[:phone].value}
                      class="input input-bordered w-full"
                      placeholder="+34 ..."
                    />
                  </div>
                </div>

                <div class="form-control">
                  <label class="label">
                    <span class="label-text font-medium">{gettext("Why do you recommend this place?")}</span>
                  </label>
                  <textarea
                    name={@form[:reason].name}
                    class="textarea textarea-bordered w-full h-28"
                    placeholder={gettext("What makes this place special? Any tips for newcomers?")}
                  >{@form[:reason].value}</textarea>
                </div>

                <div class="divider my-1"></div>

                <div class="flex justify-end gap-3">
                  <.link navigate={~p"/"} class="btn btn-ghost">{gettext("Cancel")}</.link>
                  <button type="submit" class="btn btn-primary">
                    <span class="hero-paper-airplane w-5 h-5"></span>
                    {gettext("Submit Recommendation")}
                  </button>
                </div>
              </.form>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
