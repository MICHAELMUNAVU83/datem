defmodule Datem.Organizations.InvitationNotifier do
  import Swoosh.Email

  alias Datem.Mailer

  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from({"Datem", "contact@example.com"})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc """
  Delivers an invitation to join an organisation.
  """
  def deliver_invitation(invitation, organization, url) do
    deliver(invitation.email, "You've been invited to join #{organization.name} on Datem", """

    ==============================

    Hi,

    You've been invited to join #{organization.name} on Datem as #{invitation.role}.

    Accept the invitation by visiting the URL below:

    #{url}

    This invitation expires on #{Calendar.strftime(invitation.expires_at, "%Y-%m-%d")}.

    If you weren't expecting this, you can ignore this email.

    ==============================
    """)
  end
end
