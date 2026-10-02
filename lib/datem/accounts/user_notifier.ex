defmodule Datem.Accounts.UserNotifier do
  alias Datem.Accounts.User

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

  # ── Shared layout ──────────────────────────────────────────────

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
                    <p style="margin:0;font-size:12px;color:#9ca3af;">Sent by Datem Visitor Management</p>
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

  # ── Account emails (existing) ──────────────────────────────────

  def deliver_update_email_instructions(user, url) do
    deliver(
      user.email,
      "Update email instructions",
      layout(
        "Confirm your new email",
        ["Hi #{user.email},", "Click below to confirm this email change."],
        {"Update email", url}
      )
    )
  end

  def deliver_login_instructions(user, url) do
    case user do
      %User{confirmed_at: nil} -> deliver_confirmation_instructions(user, url)
      _ -> deliver_magic_link_instructions(user, url)
    end
  end

  defp deliver_magic_link_instructions(user, url) do
    deliver(
      user.email,
      "Log in instructions",
      layout(
        "Log in to your account",
        ["Hi #{user.email},", "Click below to log in. If you didn't request this, ignore this email."],
        {"Log in", url}
      )
    )
  end

  defp deliver_confirmation_instructions(user, url) do
    deliver(
      user.email,
      "Confirmation instructions",
      layout(
        "Confirm your account",
        ["Hi #{user.email},", "Click below to confirm your account."],
        {"Confirm account", url}
      )
    )
  end

  # ── Visitor / host emails (new) ─────────────────────────────────

  @doc "Sent to the visitor right after they submit the form."
  def deliver_visit_confirmation(visitor, email) do
    deliver(
      email,
      "We've received your registration",
      layout(
        "You're registered, #{visitor.name}",
        [
          "Thanks for registering your visit.",
          "Your host has been notified and needs to approve the visit before your pass is issued. You'll get a follow-up email with your QR code as soon as that happens."
        ]
      )
    )
  end

  @doc "Sent to the host employee, asking them to approve the visit."
  def deliver_visit_approval_request(employee, visitor, approve_url) do
    deliver(
      employee.email,
      "Visitor waiting for your approval",
      layout(
        "#{visitor.name} wants to visit you",
        [
          "#{visitor.name}#{if visitor.company, do: " from #{visitor.company}", else: ""} has registered to visit you.",
          "Purpose: #{visitor.purpose || "Not specified"}",
          "Approve the visit to issue their entry pass."
        ],
        {"Review & approve", approve_url}
      )
    )
  end

def deliver_visit_pass(visitor, email, _pass, qr_png) do
  deliver(
    email,
    "Your visit is approved — here's your pass",
    layout(
      "You're all set, #{visitor.name}",
      [
        "Your visit has been approved.",
        "Your QR pass is attached — show it at the gate."
      ]
    ),
    [{"visitor-pass.png", "image/png", qr_png}]
  )
end

  def deliver_employee_pass_request(email, pass, review_url) do
  who = if pass.for_self, do: pass.employee.name, else: "#{pass.requested_by.name} (on behalf of #{pass.employee.name})"

  deliver(
    email,
    "Exit pass request awaiting your approval",
    layout(
      "#{pass.employee.name} needs to step out",
      [
        "Requested by: #{who}",
        "Reason: #{pass.reason}",
        pass.expected_departure_at &&
          "From: #{Datem.NairobiTime.format(pass.expected_departure_at, "%d %b %Y, %H:%M")}",
        pass.expected_return_at &&
          "Expected back: #{Datem.NairobiTime.format(pass.expected_return_at, "%d %b %Y, %H:%M")}"
      ]
      |> Enum.filter(& &1),
      {"Review this request", review_url}
    )
  )
end

def deliver_employee_pass_decision(email, pass) do
  status = if pass.status == "approved", do: "approved", else: "denied"
  reason_line = pass.decision_reason && "Reason given: #{pass.decision_reason}"

  deliver(
    email,
    "Your exit pass was #{status}",
    layout("Your exit pass was #{status}", [reason_line] |> Enum.filter(& &1))
  )
end

def deliver_item_pass_request(email, pass, review_url) do
  kind = if pass.returnable, do: "returnable", else: "non-returnable"

  deliver(
    email,
    "Item pass request awaiting your approval",
    layout(
      "#{pass.requested_by.name} wants to take: #{pass.item_name}",
      ["Type: #{kind}", "Reason: #{pass.reason}"],
      {"Review this request", review_url}
    )
  )
end

def deliver_item_pass_decision(email, pass) do
  status = if pass.status == "approved", do: "approved", else: "denied"
  reason_line = pass.decision_reason && "Reason given: #{pass.decision_reason}"

  deliver(
    email,
    "Your item pass was #{status}",
    layout("Your item pass for #{pass.item_name} was #{status}", [reason_line] |> Enum.filter(& &1))
  )
end

def deliver_car_pass_request(email, pass, review_url) do
  vehicle_label = pass.vehicle && pass.vehicle.plate || "Unassigned vehicle"

  deliver(
    email,
    "Car pass request awaiting your approval",
    layout(
      "#{pass.requested_by.name} needs #{vehicle_label} — #{pass.serial}",
      ["Carrying: #{pass.carrying || "—"}", "Reason: #{pass.reason}"],
      {"Review this request", review_url}
    )
  )
end

def deliver_car_pass_decision(email, pass) do
  status = if pass.status == "approved", do: "approved", else: "denied"
  reason_line = pass.decision_reason && "Reason given: #{pass.decision_reason}"

  deliver(
    email,
    "Car pass #{pass.serial} was #{status}",
    layout("Car pass #{pass.serial} was #{status}", [reason_line] |> Enum.filter(& &1))
  )
end

  @doc "Sent to a department head when someone requests an exit pass they need to approve."
def deliver_employee_pass_request(email, pass, approve_url, deny_url) do
  who = if pass.for_self, do: pass.employee.name, else: "#{pass.requested_by.name} (on behalf of #{pass.employee.name})"

  deliver(
    email,
    "Exit pass request awaiting your approval",
    layout(
      "#{pass.employee.name} needs to step out",
      ["Requested by: #{who}", "Reason: #{pass.reason}"],
      {"Review this request", approve_url}
    ) <> extra_link(deny_url, "Deny instead")
  )
end



@doc "Sent to a department head when someone requests to take a company asset off-site."
def deliver_item_pass_request(email, pass, approve_url, deny_url) do
  kind = if pass.returnable, do: "returnable", else: "non-returnable"

  deliver(
    email,
    "Item pass request awaiting your approval",
    layout(
      "#{pass.requested_by.name} wants to take: #{pass.item_name}",
      ["Type: #{kind}", "Reason: #{pass.reason}"],
      {"Review this request", approve_url}
    ) <> extra_link(deny_url, "Deny instead")
  )
end

@doc "Sent to the requester once their item pass is approved or denied."
def deliver_item_pass_decision(email, pass) do
  status = if pass.status == "approved", do: "approved", else: "denied"

  deliver(
    email,
    "Your item pass was #{status}",
    layout("Your item pass for #{pass.item_name} was #{status}", ["Reason given: #{pass.reason}"])
  )
end

defp extra_link(url, text),
  do: "<p style=\"margin:8px 0 0;font-size:13px;\"><a href=\"#{url}\">#{text}</a></p>"
end
