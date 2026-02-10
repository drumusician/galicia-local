defmodule GaliciaLocal.Mailer.EmailLayout do
  @moduledoc """
  Shared email layout for consistent styling across all transactional emails.
  """

  def wrap(content) do
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
    </head>
    <body style="margin: 0; padding: 0; background-color: #f4f4f5; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background-color: #f4f4f5; padding: 40px 20px;">
        <tr>
          <td align="center">
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width: 480px; background-color: #ffffff; border-radius: 12px; overflow: hidden; box-shadow: 0 1px 3px rgba(0,0,0,0.1);">
              <!-- Header -->
              <tr>
                <td style="background-color: #4f46e5; padding: 24px 32px; text-align: center;">
                  <span style="font-size: 24px; margin-right: 8px;">&#x1F4CD;</span>
                  <span style="color: #ffffff; font-size: 22px; font-weight: 700; letter-spacing: -0.5px; vertical-align: middle;">StartLocal</span>
                </td>
              </tr>
              <!-- Content -->
              <tr>
                <td style="padding: 32px;">
                  #{content}
                </td>
              </tr>
              <!-- Footer -->
              <tr>
                <td style="padding: 20px 32px; border-top: 1px solid #e4e4e7; text-align: center;">
                  <p style="margin: 0; font-size: 13px; color: #a1a1aa;">
                    <a href="https://startlocal.app" style="color: #4f46e5; text-decoration: none;">startlocal.app</a>
                    &nbsp;&middot;&nbsp; Your local guide to life abroad
                  </p>
                </td>
              </tr>
            </table>
          </td>
        </tr>
      </table>
    </body>
    </html>
    """
  end

  def button(url, label) do
    """
    <table role="presentation" cellpadding="0" cellspacing="0" style="margin: 24px 0;">
      <tr>
        <td style="background-color: #4f46e5; border-radius: 8px;">
          <a href="#{url}" style="display: inline-block; padding: 12px 32px; color: #ffffff; font-size: 16px; font-weight: 600; text-decoration: none;">#{label}</a>
        </td>
      </tr>
    </table>
    """
  end

  def fallback_link(url) do
    """
    <p style="margin: 16px 0 0; font-size: 13px; color: #a1a1aa;">
      Or copy and paste this link into your browser:<br>
      <a href="#{url}" style="color: #4f46e5; word-break: break-all;">#{url}</a>
    </p>
    """
  end

  def paragraph(text) do
    """
    <p style="margin: 0 0 16px; font-size: 15px; line-height: 1.6; color: #27272a;">#{text}</p>
    """
  end
end
