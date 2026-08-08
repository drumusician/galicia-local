defmodule GaliciaLocalWeb.Plugs.RateLimitAuth do
  @moduledoc """
  Caps how often a single client can hit the auth endpoints that send email.

  `POST /auth/user/password/register`, `.../password/reset_request` and
  `.../magic_link/request` each cause a Postmark delivery, and the magic link
  and register endpoints also create a user row. Automated signups abuse
  exactly these three, which costs real money per send and — more expensively —
  burns sender reputation on bounces.

  A human hits these once, maybe twice if the first mail goes missing. The
  limit is set well above that and shared across the three endpoints, so a
  legitimate user cannot realistically reach it while a script does so
  immediately.

  Sign-in is intentionally not limited here: a wrong password costs nothing,
  and shared NAT would make a strict limit lock out real people.
  """

  @behaviour Plug

  import Plug.Conn
  import Phoenix.Controller, only: [put_flash: 3, redirect: 2]

  require Logger

  @email_sending_paths [
    ~w(auth user password register),
    ~w(auth user password reset_request),
    ~w(auth user magic_link request)
  ]

  @limit 5
  @window :timer.hours(1)

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{method: "POST"} = conn, _opts) do
    if conn.path_info in @email_sending_paths do
      enforce(conn)
    else
      conn
    end
  end

  def call(conn, _opts), do: conn

  defp enforce(conn) do
    ip = client_ip(conn)

    case GaliciaLocalWeb.RateLimit.check({:auth_email, ip}, @limit, @window) do
      :ok ->
        conn

      {:error, retry_after} ->
        Logger.info("Rate limited auth request from #{ip} to /#{Enum.join(conn.path_info, "/")}")

        conn
        |> put_resp_header("retry-after", to_string(retry_after))
        |> put_flash(:error, "Too many attempts. Please try again later.")
        |> redirect(to: "/sign-in")
        |> halt()
    end
  end

  # Fly's proxy sets fly-client-ip and overwrites any client-supplied value, so
  # it is both accurate and unspoofable. Without it `remote_ip` would be the
  # proxy itself for every request, which would put all traffic in one bucket —
  # so fall back only when the header is absent, i.e. off Fly.
  defp client_ip(conn) do
    case get_req_header(conn, "fly-client-ip") do
      [ip | _] when ip != "" -> ip
      _ -> conn.remote_ip |> :inet.ntoa() |> to_string()
    end
  end
end
