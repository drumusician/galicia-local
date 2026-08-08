defmodule GaliciaLocal.Accounts.StaleSignupCleanupTest do
  use GaliciaLocal.DataCase, async: false

  alias GaliciaLocal.Accounts.StaleSignupCleanup
  alias GaliciaLocal.Accounts.User
  alias GaliciaLocal.Community.Suggestion

  @old ~U[2020-01-01 00:00:00.000000Z]

  defp seed_user(attrs) do
    Ash.Seed.seed!(
      User,
      Map.merge(%{email: "#{System.unique_integer([:positive])}@example.com"}, attrs)
    )
  end

  defp emails do
    User
    |> Ash.read!(authorize?: false)
    |> Enum.map(&to_string(&1.email))
    |> MapSet.new()
  end

  test "deletes old unconfirmed signups" do
    spam = seed_user(%{confirmed_at: nil, inserted_at: @old})

    assert 1 = StaleSignupCleanup.sweep_now(7)
    refute to_string(spam.email) in emails()
  end

  test "keeps confirmed users no matter how old" do
    confirmed = seed_user(%{confirmed_at: @old, inserted_at: @old})

    assert 0 = StaleSignupCleanup.sweep_now(7)
    assert to_string(confirmed.email) in emails()
  end

  test "keeps unconfirmed signups inside the retention window" do
    recent = seed_user(%{confirmed_at: nil, inserted_at: DateTime.utc_now()})

    assert 0 = StaleSignupCleanup.sweep_now(7)
    assert to_string(recent.email) in emails()
  end

  test "keeps admins even when unconfirmed and old" do
    admin = seed_user(%{confirmed_at: nil, inserted_at: @old, is_admin: true})

    assert 0 = StaleSignupCleanup.sweep_now(7)
    assert to_string(admin.email) in emails()
  end

  test "keeps unconfirmed users that left content behind" do
    # Also guards the foreign key: suggestions.user_id has no ON DELETE, so
    # deleting this user would raise rather than silently orphan the row.
    author = seed_user(%{confirmed_at: nil, inserted_at: @old})

    Ash.Seed.seed!(Suggestion, %{
      user_id: author.id,
      business_name: "Cafe Test",
      city_name: "Vigo"
    })

    assert 0 = StaleSignupCleanup.sweep_now(7)
    assert to_string(author.email) in emails()
  end

  test "the destroy action added for cleanup is not reachable by users" do
    # No policy covers :destroy, so it must only work via the sweep's
    # authorize?: false. Adding a permissive policy here would let any signed-in
    # user delete any account.
    victim = seed_user(%{confirmed_at: @old, inserted_at: @old})
    actor = seed_user(%{confirmed_at: @old, inserted_at: @old})

    # Naming the action explicitly still hits the policy check and is refused.
    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.destroy(victim, action: :destroy, actor: actor)

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.destroy(victim, action: :destroy, actor: nil)

    # And it is not the primary destroy, so a bare Ash.destroy/1 finds nothing.
    assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Invalid.NoPrimaryAction{}]}} =
             Ash.destroy(victim, actor: actor)

    assert to_string(victim.email) in emails()
  end

  test "removes only the stale rows when the table is mixed" do
    spam = seed_user(%{confirmed_at: nil, inserted_at: @old})
    confirmed = seed_user(%{confirmed_at: @old, inserted_at: @old})
    recent = seed_user(%{confirmed_at: nil, inserted_at: DateTime.utc_now()})

    assert 1 = StaleSignupCleanup.sweep_now(7)

    remaining = emails()
    refute to_string(spam.email) in remaining
    assert to_string(confirmed.email) in remaining
    assert to_string(recent.email) in remaining
  end
end
