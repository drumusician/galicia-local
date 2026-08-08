defmodule GaliciaLocalWeb.Plugs.RateLimitAuthTest do
  use GaliciaLocalWeb.ConnCase, async: false

  alias GaliciaLocalWeb.RateLimit

  @limit 5
  @register "/auth/user/password/register"

  setup do
    :ets.delete_all_objects(RateLimit)
    :ok
  end

  defp register(ip) do
    build_conn()
    |> put_req_header("fly-client-ip", ip)
    |> post(@register, %{"user" => %{"email" => "a@example.com", "password" => "password1234"}})
  end

  test "blocks further attempts once the limit is passed" do
    for _ <- 1..@limit do
      refute redirected_to_sign_in?(register("9.9.9.1"))
    end

    conn = register("9.9.9.1")
    assert redirected_to(conn) == "/sign-in"
    assert get_resp_header(conn, "retry-after") != []
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Too many attempts"
  end

  test "limits each client IP independently" do
    for _ <- 1..(@limit + 1), do: register("9.9.9.2")

    # A different visitor must not inherit the blocked client's counter.
    refute redirected_to_sign_in?(register("9.9.9.3"))
  end

  test "does not limit sign in" do
    for _ <- 1..(@limit + 3) do
      conn =
        build_conn()
        |> put_req_header("fly-client-ip", "9.9.9.4")
        |> post("/auth/user/password/sign_in", %{
          "user" => %{"email" => "a@example.com", "password" => "wrongpassword"}
        })

      refute redirected_to_sign_in?(conn)
    end
  end

  test "does not limit GET requests to auth pages" do
    for _ <- 1..(@limit + 3) do
      conn =
        build_conn()
        |> put_req_header("fly-client-ip", "9.9.9.5")
        |> get("/register")

      assert conn.status == 200
    end
  end

  # The plug redirects to /sign-in on block. Auth failures redirect elsewhere
  # (or render), so this distinguishes "rate limited" from "bad credentials".
  defp redirected_to_sign_in?(conn) do
    conn.status in 300..399 and
      get_resp_header(conn, "location") == ["/sign-in"] and
      Phoenix.Flash.get(conn.assigns[:flash] || %{}, :error) =~ "Too many attempts"
  end
end
