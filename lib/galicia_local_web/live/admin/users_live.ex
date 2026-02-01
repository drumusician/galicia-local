defmodule GaliciaLocalWeb.Admin.UsersLive do
  @moduledoc """
  Admin interface for viewing and managing users.
  """
  use GaliciaLocalWeb, :live_view

  alias GaliciaLocal.Accounts.User

  @impl true
  def mount(_params, _session, socket) do
    users = load_users()

    {:ok,
     socket
     |> assign(:page_title, "Manage Users")
     |> assign(:users, users)}
  end

  defp load_users do
    User.list!()
    |> Ash.load!([:city])
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
  end

  @impl true
  def handle_event("toggle_admin", %{"id" => id}, socket) do
    current_user = socket.assigns.current_user

    case User.get_by_id(id) do
      {:ok, user} ->
        if user.id == current_user.id do
          {:noreply, put_flash(socket, :error, "You cannot change your own admin status")}
        else
          case Ash.update(user, %{is_admin: !user.is_admin}, action: :admin_update) do
            {:ok, _} ->
              {:noreply,
               socket
               |> assign(:users, load_users())
               |> put_flash(:info, "User updated")}

            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Failed to update user")}
          end
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "User not found")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200">
      <header class="bg-base-100 border-b border-base-300 sticky top-0 z-50">
        <div class="container mx-auto px-6 py-4">
          <div class="flex items-center gap-4">
            <.link navigate={~p"/admin"} class="btn btn-ghost btn-sm">
              <span class="hero-arrow-left w-4 h-4"></span>
            </.link>
            <div>
              <h1 class="text-2xl font-bold">Users</h1>
              <p class="text-sm text-base-content/60">{length(@users)} registered users</p>
            </div>
          </div>
        </div>
      </header>

      <main class="container mx-auto px-6 py-8">
        <div class="card bg-base-100 shadow-xl">
          <div class="card-body p-0">
            <div class="overflow-x-auto">
              <table class="table">
                <thead>
                  <tr>
                    <th>User</th>
                    <th>Location</th>
                    <th>Joined</th>
                    <th>Admin</th>
                    <th></th>
                  </tr>
                </thead>
                <tbody>
                  <%= for user <- @users do %>
                    <tr>
                      <td>
                        <div>
                          <p class="font-medium">{user.display_name || "—"}</p>
                          <p class="text-sm text-base-content/60">{user.email}</p>
                        </div>
                      </td>
                      <td class="text-sm">
                        {if user.city, do: user.city.name, else: "—"}
                        <%= if user.origin_country && user.origin_country != "" do %>
                          <span class="text-base-content/50">· {user.origin_country}</span>
                        <% end %>
                      </td>
                      <td class="text-sm text-base-content/60">
                        {Calendar.strftime(user.inserted_at, "%b %d, %Y")}
                      </td>
                      <td>
                        <%= if user.is_admin do %>
                          <span class="badge badge-primary badge-sm">Admin</span>
                        <% end %>
                      </td>
                      <td>
                        <%= if user.id != @current_user.id do %>
                          <button
                            type="button"
                            phx-click="toggle_admin"
                            phx-value-id={user.id}
                            class={["btn btn-xs", if(user.is_admin, do: "btn-error btn-outline", else: "btn-ghost")]}
                            data-confirm={if user.is_admin, do: "Remove admin access for #{user.email}?", else: "Grant admin access to #{user.email}?"}
                          >
                            {if user.is_admin, do: "Remove Admin", else: "Make Admin"}
                          </button>
                        <% else %>
                          <span class="text-xs text-base-content/40">You</span>
                        <% end %>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          </div>
        </div>
      </main>
    </div>
    """
  end
end
