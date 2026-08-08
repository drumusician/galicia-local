defmodule GaliciaLocal.Accounts.DisposableEmailDomainsTest do
  use GaliciaLocal.DataCase, async: false

  import Swoosh.TestAssertions

  alias GaliciaLocal.Accounts.DisposableEmailDomains, as: Disposable
  alias GaliciaLocal.Accounts.User
  alias GaliciaLocal.Accounts.User.Senders.SendMagicLinkEmail

  describe "disposable?/1" do
    test "flags a listed domain" do
      assert Disposable.disposable?("spammer@mailinator.com")
      assert Disposable.disposable?("x@guerrillamail.com")
      assert Disposable.disposable?("x@10minutemail.com")
    end

    test "flags subdomains of a listed domain" do
      # These services hand out arbitrary subdomains, so an exact-match-only
      # check would let every one of them through.
      assert Disposable.disposable?("x@foo.mailinator.com")
      assert Disposable.disposable?("x@deeply.nested.mailinator.com")
    end

    test "is case insensitive" do
      assert Disposable.disposable?("X@MailInAtor.CoM")
    end

    test "allows ordinary providers" do
      refute Disposable.disposable?("tjaco@smart-code.nl")
      refute Disposable.disposable?("someone@gmail.com")
      refute Disposable.disposable?("someone@outlook.com")
      refute Disposable.disposable?("someone@startlocal.app")
    end

    test "does not block a domain merely containing a listed one" do
      # "notmailinator.com" is listed, but "mailinator.com.example.org" is not
      # a subdomain of it and must not be caught by a naive substring check.
      refute Disposable.disposable?("x@mailinator.com.example.org")
      refute Disposable.disposable?("x@notreallymailinator.com")
    end

    test "returns false for input that is not an address" do
      refute Disposable.disposable?("no-at-sign")
      refute Disposable.disposable?("trailing@")
      refute Disposable.disposable?("")
      refute Disposable.disposable?(nil)
    end

    test "accepts a ci_string, which is what the action passes in" do
      assert Disposable.disposable?(Ash.CiString.new("x@mailinator.com"))
      refute Disposable.disposable?(Ash.CiString.new("x@gmail.com"))
    end
  end

  describe "registration" do
    defp register(email) do
      Ash.create(
        User,
        %{email: email, password: "password1234", password_confirmation: "password1234"},
        action: :register_with_password,
        authorize?: false
      )
    end

    test "rejects a throwaway address with a message on the email field" do
      assert {:error, %Ash.Error.Invalid{} = error} = register("spammer@mailinator.com")

      assert Enum.any?(error.errors, fn e ->
               Map.get(e, :field) == :email and
                 Exception.message(e) =~ "permanent email address"
             end)
    end

    test "still accepts a normal address" do
      assert {:ok, user} = register("real.person@gmail.com")
      assert to_string(user.email) == "real.person@gmail.com"
    end
  end

  describe "magic link sender" do
    test "sends nothing to a throwaway address" do
      assert :ok = SendMagicLinkEmail.send("spammer@mailinator.com", "tok", [])
      refute_email_sent()
    end

    test "still sends to a normal address" do
      SendMagicLinkEmail.send("real.person@gmail.com", "tok", [])
      assert_email_sent(to: [{"", "real.person@gmail.com"}])
    end
  end
end
