defmodule GaliciaLocalWeb.RateLimitTest do
  use ExUnit.Case, async: false

  alias GaliciaLocalWeb.RateLimit

  # RateLimit is started by the application supervisor, so tests share the one
  # instance and just clear its counters between runs.
  setup do
    :ets.delete_all_objects(RateLimit)
    :ok
  end

  test "allows up to the limit and blocks after it" do
    window = :timer.hours(1)

    for _ <- 1..3 do
      assert :ok = RateLimit.check({:auth_email, "1.1.1.1"}, 3, window)
    end

    assert {:error, retry_after} = RateLimit.check({:auth_email, "1.1.1.1"}, 3, window)
    assert retry_after > 0
    assert retry_after <= div(window, 1000) + 1
  end

  test "counts each key separately" do
    window = :timer.hours(1)

    assert {:error, _} =
             Enum.reduce(1..2, :ok, fn _, _ ->
               RateLimit.check({:auth_email, "2.2.2.2"}, 1, window)
             end)

    assert :ok = RateLimit.check({:auth_email, "3.3.3.3"}, 1, window)
  end

  test "buckets with different window sizes coexist" do
    assert :ok = RateLimit.check({:short, "4.4.4.4"}, 1, 1_000)
    assert :ok = RateLimit.check({:long, "4.4.4.4"}, 1, :timer.hours(1))
    assert {:error, _} = RateLimit.check({:short, "4.4.4.4"}, 1, 1_000)
    assert {:error, _} = RateLimit.check({:long, "4.4.4.4"}, 1, :timer.hours(1))
  end

  test "purging drops expired windows but keeps live ones" do
    # An hour-long window must survive a purge. The first implementation
    # computed expiry from a hardcoded window size, so it deleted live
    # long-window counters and silently reset the limit on every sweep.
    expired_key = {{:expired, "5.5.5.5"}, 0}
    :ets.insert(RateLimit, {expired_key, 99, System.system_time(:millisecond) - 1_000})

    assert :ok = RateLimit.check({:live, "5.5.5.5"}, 1, :timer.hours(1))

    send(Process.whereis(RateLimit), :purge)
    _ = :sys.get_state(RateLimit)

    assert [] = :ets.lookup(RateLimit, expired_key)
    assert {:error, _} = RateLimit.check({:live, "5.5.5.5"}, 1, :timer.hours(1))
  end

  test "fails open when the limiter is not running" do
    :ok = Supervisor.terminate_child(GaliciaLocal.Supervisor, RateLimit)
    on_exit(fn -> Supervisor.restart_child(GaliciaLocal.Supervisor, RateLimit) end)

    # Without the rescue this would raise ArgumentError on the missing table and
    # take every signup down with it.
    assert :ok = RateLimit.check({:auth_email, "6.6.6.6"}, 1, 1_000)
    assert :ok = RateLimit.check({:auth_email, "6.6.6.6"}, 1, 1_000)
  end
end
