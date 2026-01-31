defmodule GaliciaLocal.Accounts.User.Senders.SendNewUserConfirmationEmail do
  @moduledoc """
  Sends an email for a new user to confirm their email address.
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
    |> subject("Confirm your email – Welcome to GaliciaLocal!")
    |> html_body(body(token: token))
    |> Mailer.deliver!()
  end

  defp body(params) do
    link_url = url(~p"/confirm_new_user/#{params[:token]}")

    content =
      EmailLayout.paragraph("Welcome to GaliciaLocal! We're glad you're here.") <>
        EmailLayout.paragraph("Please confirm your email address by clicking the button below to get started.") <>
        EmailLayout.button(link_url, "Confirm Email") <>
        EmailLayout.paragraph("If you didn't create an account, you can safely ignore this email.") <>
        EmailLayout.fallback_link(link_url)

    EmailLayout.wrap(content)
  end
end
