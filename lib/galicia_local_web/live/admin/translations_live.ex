defmodule GaliciaLocalWeb.Admin.TranslationsLive do
  use GaliciaLocalWeb, :live_view

  alias GaliciaLocal.Directory.TranslationStatus
  alias GaliciaLocal.Workers.TranslateWorker

  @locale_labels %{
    "es" => {"Español", "🇪🇸"},
    "nl" => {"Nederlands", "🇳🇱"}
  }

  @impl true
  def mount(_params, _session, socket) do
    region = socket.assigns[:current_region]
    region_id = if region, do: region.id

    {:ok,
     socket
     |> assign(:page_title, "Translations")
     |> assign(:region_id, region_id)
     |> assign(:locale_labels, @locale_labels)
     |> assign(:queuing, nil)
     |> assign(:last_queued, nil)
     |> load_status()}
  end

  @impl true
  def handle_event("translate_missing", %{"type" => type, "locale" => locale}, socket) do
    region_id = socket.assigns.region_id

    ids = get_missing_ids(type, locale, region_id)
    count = length(ids)

    if count > 0 do
      socket = assign(socket, :queuing, "#{type}/#{locale}")

      jobs =
        Enum.map(ids, fn id ->
          TranslateWorker.new(%{type: type, id: id, target_locale: locale})
        end)

      Oban.insert_all(jobs)

      {:noreply,
       socket
       |> assign(:queuing, nil)
       |> assign(:last_queued, "Queued #{count} #{type} translations for #{locale}")
       |> load_status()}
    else
      {:noreply, assign(socket, :last_queued, "Nothing to translate for #{type}/#{locale}")}
    end
  end

  def handle_event("translate_all_missing", _params, socket) do
    region_id = socket.assigns.region_id
    total = 0

    {jobs, total} =
      for locale <- TranslationStatus.target_locales(),
          type <- ["business", "category", "city"],
          reduce: {[], total} do
        {acc_jobs, acc_total} ->
          ids = get_missing_ids(type, locale, region_id)

          new_jobs =
            Enum.map(ids, fn id ->
              TranslateWorker.new(%{type: type, id: id, target_locale: locale})
            end)

          {acc_jobs ++ new_jobs, acc_total + length(ids)}
      end

    if total > 0 do
      Oban.insert_all(jobs)
    end

    {:noreply,
     socket
     |> assign(:last_queued, "Queued #{total} translation jobs")
     |> load_status()}
  end

  defp get_missing_ids("business", locale, region_id), do: TranslationStatus.missing_business_ids(locale, region_id)
  defp get_missing_ids("category", locale, _region_id), do: TranslationStatus.missing_category_ids(locale)
  defp get_missing_ids("city", locale, region_id), do: TranslationStatus.missing_city_ids(locale, region_id)

  defp load_status(socket) do
    status = TranslationStatus.summary(region_id: socket.assigns.region_id)
    assign(socket, :status, status)
  end

  defp percentage(count, total) when total > 0, do: round(count / total * 100)
  defp percentage(_count, _total), do: 0

  defp progress_color(pct) when pct >= 90, do: "progress-success"
  defp progress_color(pct) when pct >= 50, do: "progress-warning"
  defp progress_color(_pct), do: "progress-error"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200">
      <div class="container mx-auto max-w-6xl px-4 py-8">
        <div class="flex items-center justify-between mb-8">
          <div class="flex items-center gap-4">
            <.link navigate={~p"/admin"} class="btn btn-ghost btn-square btn-sm">
              <span class="hero-arrow-left w-5 h-5"></span>
            </.link>
            <div>
              <h1 class="text-3xl font-bold">Translations</h1>
              <p class="text-base-content/60 mt-1">Translation completeness overview. Uses DeepL for translations.</p>
            </div>
          </div>
          <button phx-click="translate_all_missing" class="btn btn-primary btn-sm">
            <span class="hero-language w-4 h-4"></span>
            Translate All Missing
          </button>
        </div>

        <%= if @last_queued do %>
          <div class="alert alert-info mb-6">
            <span class="hero-information-circle w-5 h-5"></span>
            <span>{@last_queued}</span>
          </div>
        <% end %>

        <div class="grid grid-cols-1 gap-6">
          <.translation_card
            title="Businesses"
            icon="hero-building-storefront"
            type="business"
            data={@status.businesses}
            locale_labels={@locale_labels}
            queuing={@queuing}
          />
          <.translation_card
            title="Categories"
            icon="hero-squares-2x2"
            type="category"
            data={@status.categories}
            locale_labels={@locale_labels}
            queuing={@queuing}
          />
          <.translation_card
            title="Cities"
            icon="hero-map-pin"
            type="city"
            data={@status.cities}
            locale_labels={@locale_labels}
            queuing={@queuing}
          />
        </div>
      </div>
    </div>
    """
  end

  defp translation_card(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow">
      <div class="card-body">
        <h2 class="card-title text-lg mb-4">
          <span class={"#{@icon} w-5 h-5 text-primary"}></span>
          {@title}
          <span class="badge badge-neutral badge-sm">{@data[:total]} total</span>
        </h2>

        <div class="space-y-4">
          <%= for locale <- GaliciaLocal.Directory.TranslationStatus.target_locales() do %>
            <% count = Map.get(@data, locale, 0) %>
            <% total = @data[:total] %>
            <% pct = percentage(count, total) %>
            <% missing = total - count %>
            <% {label, flag} = Map.get(@locale_labels, locale, {locale, ""}) %>

            <div class="flex items-center gap-4">
              <div class="w-24 flex items-center gap-2">
                <span class="text-lg">{flag}</span>
                <span class="text-sm font-medium">{label}</span>
              </div>

              <div class="flex-1">
                <progress class={"progress #{progress_color(pct)} w-full"} value={count} max={total}>
                </progress>
              </div>

              <div class="w-32 text-right">
                <span class="text-sm font-mono">{count}/{total}</span>
                <span class={"text-xs ml-1 #{if pct == 100, do: "text-success", else: "text-base-content/50"}"}>
                  ({pct}%)
                </span>
              </div>

              <div class="w-40 text-right">
                <%= if missing > 0 do %>
                  <button
                    phx-click="translate_missing"
                    phx-value-type={@type}
                    phx-value-locale={locale}
                    class="btn btn-primary btn-xs"
                    disabled={@queuing == "#{@type}/#{locale}"}
                  >
                    <%= if @queuing == "#{@type}/#{locale}" do %>
                      <span class="loading loading-spinner loading-xs"></span>
                    <% else %>
                      <span class="hero-language w-3 h-3"></span>
                    <% end %>
                    Translate {missing}
                  </button>
                <% else %>
                  <span class="badge badge-success badge-sm">Complete</span>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
