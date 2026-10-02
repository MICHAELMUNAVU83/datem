defmodule Datem.Ticketing.TicketNotifier do
  @moduledoc """
  Emails an attendee their ticket QR code. Mirrors
  `Datem.Accounts.UserNotifier`'s Finch-based delivery to Mailsafi rather
  than Swoosh, so both notifiers share one transport and one visual layout
  across the app.
  """

  @finch Datem.Finch
  @from_address "no-reply@gs1kenya.org"
  @api_url "https://postalmail.mailsafi.com/api/v1/send/message"
  @api_key "mN7wDg5akuwsNCCL4IyWSf0B"



  defp deliver(recipient, subject, html, attachments \\ []) do
    body =
      %{
        "to" => [recipient],
        "from" => @from_address,
        "subject" => subject,
        "html_body" => html
      }
      |> maybe_put_attachments(attachments)

    headers = [
      {"Content-Type", "application/json"},
      {"X-Server-API-Key", @api_key}
    ]

    :post
    |> Finch.build(@api_url, headers, Jason.encode!(body))
    |> Finch.request(@finch)
    |> response()
  end

  defp maybe_put_attachments(body, []), do: body

  defp maybe_put_attachments(body, attachments) do
    Map.put(
      body,
      "attachments",
      Enum.map(attachments, fn {filename, content_type, data} ->
        %{
          "filename" => filename,
          "content_type" => content_type,
          "content" => Base.encode64(data)
        }
      end)
    )
  end

  defp response({:ok, %Finch.Response{status: status, body: resp_body}}) when status in 200..299,
    do: {:ok, resp_body}

  defp response({:ok, %Finch.Response{status: status, body: resp_body}}),
    do: {:error, {status, resp_body}}

  defp response({:error, reason}), do: {:error, reason}

  # ── Shared layout (identical to Datem.Accounts.UserNotifier's) ──

  defp layout(heading, paragraphs, cta \\ nil) do
    """
    <!doctype html>
    <html>
      <body style="margin:0;padding:0;background:#f4f5f7;font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f5f7;padding:32px 0;">
          <tr>
            <td align="center">
              <table role="presentation" width="480" cellpadding="0" cellspacing="0" style="background:#ffffff;border-radius:12px;overflow:hidden;">
                <tr>
                  <td style="background:#111827;padding:20px 32px;">
                    <span style="color:#ffffff;font-size:16px;font-weight:600;letter-spacing:0.3px;">Datem</span>
                  </td>
                </tr>
                <tr>
                  <td style="padding:32px;">
                    <h1 style="margin:0 0 16px;font-size:19px;color:#111827;">#{heading}</h1>
                    #{Enum.map_join(paragraphs, "", &paragraph_html/1)}
                    #{cta_html(cta)}
                  </td>
                </tr>
                <tr>
                  <td style="padding:16px 32px;background:#f9fafb;">
                    <p style="margin:0;font-size:12px;color:#9ca3af;">Sent by Datem Ticketing</p>
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

  defp paragraph_html(text),
    do: "<p style=\"margin:0 0 16px;font-size:15px;line-height:1.5;color:#374151;\">#{text}</p>"

  defp cta_html(nil), do: ""

  defp cta_html({text, url}) do
    """
    <table role="presentation" cellpadding="0" cellspacing="0" style="margin-top:4px;">
      <tr>
        <td style="border-radius:8px;background:#2563eb;">
          <a href="#{url}" style="display:inline-block;padding:12px 24px;font-size:15px;color:#ffffff;text-decoration:none;font-weight:600;">#{text}</a>
        </td>
      </tr>
    </table>
    """
  end

  # ── Ticket emails ─────────────────────────────────────────────

  @doc "Emails an attendee their ticket QR code as a PNG attachment."
  def deliver_ticket(ticket, event, qr_png) do
    paragraphs =
      [
        "You're registered for #{event.name}.",
        event.venue && "Venue: #{event.venue}",
        event.starts_at &&
          "Starts: #{Calendar.strftime(event.starts_at, "%d %b %Y, %H:%M")}",
        "Your ticket QR code is attached — show it at the door to check in."
      ]
      |> Enum.filter(& &1)

    deliver(
      ticket.attendee_email,
      "Your ticket for #{event.name}",
      layout("You're registered, #{ticket.attendee_name}", paragraphs),
      [{"ticket.png", "image/png", qr_png}]
    )
  end
end
