defmodule Datem.Ticketing.TicketNotifier do
  import Swoosh.Email

  alias Datem.Mailer

  defp deliver(recipient, subject, body, attachments) do
    email =
      new()
      |> to(recipient)
      |> from({"Datem", "contact@example.com"})
      |> subject(subject)
      |> text_body(body)
      |> then(fn email -> Enum.reduce(attachments, email, &attachment(&2, &1)) end)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc """
  Emails an attendee their ticket QR code as a PNG attachment.
  """
  def deliver_ticket(ticket, event, qr_png) do
    attachment =
      Swoosh.Attachment.new({:data, qr_png}, filename: "ticket.png", content_type: "image/png")

    deliver(
      ticket.attendee_email,
      "Your ticket for #{event.name}",
      """

      ==============================

      Hi #{ticket.attendee_name},

      You're registered for #{event.name}. Your ticket QR code is attached —
      show it at the door to check in.

      ==============================
      """,
      [attachment]
    )
  end
end
