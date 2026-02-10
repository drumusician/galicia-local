defmodule GaliciaLocal.Accounts.User.Senders.SendMagicLinkEmail do
  @moduledoc """
  Sends a magic link email
  """

  use AshAuthentication.Sender
  use GaliciaLocalWeb, :verified_routes

  import Swoosh.Email
  alias GaliciaLocal.Mailer
  alias GaliciaLocal.Mailer.EmailLayout

  @impl true
  def send(user_or_email, token, _) do
    email =
      case user_or_email do
        %{email: email} -> email
        email -> email
      end

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
        EmailLayout.paragraph("This link will expire in 10 minutes. If you didn't request this, you can safely ignore this email.") <>
        EmailLayout.fallback_link(link_url)

    EmailLayout.wrap(content)
  end
end
