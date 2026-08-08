defmodule GaliciaLocal.Accounts.User.Senders.SendMagicLinkEmail do
  @moduledoc """
  Sends a magic link email
  """

  use AshAuthentication.Sender
  use GaliciaLocalWeb, :verified_routes

  import Swoosh.Email
  alias GaliciaLocal.Accounts.DisposableEmailDomains
  alias GaliciaLocal.Mailer
  alias GaliciaLocal.Mailer.EmailLayout

  @impl true
  def send(user_or_email, token, opts) do
    email =
      case user_or_email do
        %{email: email} -> email
        email -> email
      end

    # Magic link registration creates the account when the token is redeemed,
    # so the registration validation never sees these addresses. Dropping the
    # mail here is what actually stops the signup, since without the link there
    # is no token to redeem. Staying silent matches how this endpoint already
    # behaves — it never reveals whether an address exists.
    if DisposableEmailDomains.disposable?(email) do
      :ok
    else
      deliver(email, token, opts)
    end
  end

  defp deliver(email, token, _opts) do
    new()
    |> from({"StartLocal", "support@startlocal.app"})
    |> to(to_string(email))
    |> subject("Your sign-in link for StartLocal")
    |> html_body(body(token: token, email: email))
    |> Mailer.deliver!()
  end

  defp body(params) do
    link_url = url(~p"/magic_link/#{params[:token]}")

    content =
      EmailLayout.paragraph("Hello! Click the button below to sign in to StartLocal.") <>
        EmailLayout.button(link_url, "Sign In") <>
        EmailLayout.paragraph(
          "This link will expire in 10 minutes. If you didn't request this, you can safely ignore this email."
        ) <>
        EmailLayout.fallback_link(link_url)

    EmailLayout.wrap(content)
  end
end
