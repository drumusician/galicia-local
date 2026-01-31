defmodule GaliciaLocal.Accounts.User.Senders.SendPasswordResetEmail do
  @moduledoc """
  Sends a password reset email
  """

  use AshAuthentication.Sender
  use GaliciaLocalWeb, :verified_routes

  import Swoosh.Email

  alias GaliciaLocal.Mailer
  alias GaliciaLocal.Mailer.EmailLayout

  @impl true
  def send(user, token, _) do
    new()
    |> from({"GaliciaLocal", "support@galicialocal.com"})
    |> to(to_string(user.email))
    |> subject("Reset your GaliciaLocal password")
    |> html_body(body(token: token))
    |> Mailer.deliver!()
  end

  defp body(params) do
    link_url = url(~p"/password-reset/#{params[:token]}")

    content =
      EmailLayout.paragraph("We received a request to reset your password.") <>
        EmailLayout.paragraph("Click the button below to choose a new password.") <>
        EmailLayout.button(link_url, "Reset Password") <>
        EmailLayout.paragraph("If you didn't request a password reset, you can safely ignore this email. Your password won't change.") <>
        EmailLayout.fallback_link(link_url)

    EmailLayout.wrap(content)
  end
end
