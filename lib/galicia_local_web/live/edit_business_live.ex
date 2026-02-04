defmodule GaliciaLocalWeb.EditBusinessLive do
  use GaliciaLocalWeb, :live_view

  alias GaliciaLocal.Directory.Business

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    region = socket.assigns[:current_region]
    region_slug = if region, do: region.slug, else: "galicia"

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
           |> assign(:form, to_form(form))
           |> assign(:region_slug, region_slug)}
        else
          {:ok,
           socket
           |> put_flash(:error, gettext("You don't have permission to edit this business"))
           |> push_navigate(to: ~p"/#{region_slug}/my-businesses")}
        end

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Business not found"))
         |> push_navigate(to: ~p"/#{region_slug}/my-businesses")}
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
    params = parse_array_fields(params)
    params = parse_opening_hours(params)

    case AshPhoenix.Form.submit(socket.assigns.form.source, params: params) do
      {:ok, business} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Business updated successfully!"))
         |> push_navigate(to: ~p"/#{socket.assigns.region_slug}/businesses/#{business.id}")}

      {:error, form} ->
        {:noreply, assign(socket, :form, to_form(form))}
    end
  end

  @days ~w(monday tuesday wednesday thursday friday saturday sunday)

  defp parse_array_fields(params) do
    ~w(highlights highlights_es service_specialties photo_urls)
    |> Enum.reduce(params, fn key, acc ->
      case acc[key] do
        nil -> acc
        "" -> Map.put(acc, key, [])
        text when is_binary(text) ->
          items = text |> String.split("\n") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
          Map.put(acc, key, items)
        _ -> acc
      end
    end)
  end

  defp parse_opening_hours(params) do
    case params["opening_hours"] do
      nil -> params
      hours ->
        parsed =
          Enum.reduce(@days, %{}, fn day, acc ->
            case hours[day] do
              nil -> acc
              "" -> acc
              val when is_binary(val) -> Map.put(acc, day, String.trim(val))
              _ -> acc
            end
          end)
        Map.put(params, "opening_hours", parsed)
    end
  end

  defp format_array(nil), do: ""
  defp format_array(list) when is_list(list), do: Enum.join(list, "\n")
  defp format_array(_), do: ""

  defp get_day_hours(business, day) do
    case business.opening_hours do
      %{^day => val} when is_binary(val) -> val
      %{^day => %{"closed" => true}} -> "Closed"
      %{^day => %{"open" => open, "close" => close}} -> "#{open} - #{close}"
      _ -> ""
    end
  end

  defp day_label(day), do: String.capitalize(day)

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :days, @days)
    ~H"""
    <div class="min-h-screen bg-base-200">
      <div class="container mx-auto max-w-3xl px-4 py-8">
        <nav class="text-sm breadcrumbs mb-6">
          <ul>
            <li><.link navigate={~p"/#{@region_slug}/my-businesses"} class="hover:text-primary">{gettext("My Businesses")}</.link></li>
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

              <fieldset class="fieldset">
                <legend class="fieldset-legend">{gettext("Short Summary (Spanish)")}</legend>
                <input type="text" name={@form[:summary_es].name} value={@form[:summary_es].value} class="input input-bordered w-full" />
              </fieldset>

              <div class="divider">{gettext("Highlights & Specialties")}</div>

              <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                <fieldset class="fieldset">
                  <legend class="fieldset-legend">{gettext("Highlights (English)")}</legend>
                  <textarea name="business[highlights]" class="textarea textarea-bordered w-full font-mono text-sm" rows="4">{format_array(@business.highlights)}</textarea>
                  <p class="fieldset-label">{gettext("One per line")}</p>
                </fieldset>

                <fieldset class="fieldset">
                  <legend class="fieldset-legend">{gettext("Highlights (Spanish)")}</legend>
                  <textarea name="business[highlights_es]" class="textarea textarea-bordered w-full font-mono text-sm" rows="4">{format_array(@business.highlights_es)}</textarea>
                  <p class="fieldset-label">{gettext("One per line")}</p>
                </fieldset>
              </div>

              <fieldset class="fieldset">
                <legend class="fieldset-legend">{gettext("Service Specialties")}</legend>
                <textarea name="business[service_specialties]" class="textarea textarea-bordered w-full font-mono text-sm" rows="3">{format_array(@business.service_specialties)}</textarea>
                <p class="fieldset-label">{gettext("One per line")}</p>
              </fieldset>

              <div class="divider">{gettext("Opening Hours")}</div>

              <div class="space-y-2">
                <%= for day <- @days do %>
                  <div class="flex items-center gap-3">
                    <span class="w-24 text-sm font-medium">{day_label(day)}</span>
                    <input
                      type="text"
                      name={"business[opening_hours][#{day}]"}
                      value={get_day_hours(@business, day)}
                      class="input input-bordered input-sm flex-1"
                      placeholder={gettext("e.g. 9:00 AM – 1:30 PM")}
                    />
                  </div>
                <% end %>
              </div>

              <div class="divider">{gettext("Photos")}</div>

              <%= if @business.photo_urls && @business.photo_urls != [] do %>
                <div class="flex flex-wrap gap-2 mb-4">
                  <%= for url <- Enum.take(@business.photo_urls, 6) do %>
                    <img src={url} class="w-20 h-20 object-cover rounded-lg" />
                  <% end %>
                </div>
              <% end %>

              <fieldset class="fieldset">
                <legend class="fieldset-legend">{gettext("Photo URLs")}</legend>
                <textarea name="business[photo_urls]" class="textarea textarea-bordered w-full font-mono text-xs" rows="4">{format_array(@business.photo_urls)}</textarea>
                <p class="fieldset-label">{gettext("One URL per line")}</p>
              </fieldset>

              <div class="card-actions justify-end mt-6">
                <.link navigate={~p"/#{@region_slug}/my-businesses"} class="btn btn-ghost">{gettext("Cancel")}</.link>
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
