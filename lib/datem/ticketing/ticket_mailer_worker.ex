defmodule Datem.Ticketing.TicketMailerWorker do
  @moduledoc """
  Emails a newly-issued ticket's QR code to its attendee. Enqueued by
  `Datem.Ticketing.register_attendee/3` right after a ticket is issued, so
  registration itself never blocks on outbound mail.
  """
  use Oban.Worker, queue: :mailers, max_attempts: 5

  import Ecto.Query, warn: false

  alias Datem.Repo
  alias Datem.GS1
  alias Datem.Ticketing.{Ticket, TicketNotifier}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"ticket_id" => ticket_id}}) do
    case Repo.get(Ticket, ticket_id) |> Repo.preload([:event, :gs1_identifier]) do
      nil ->
        :ok

      %Ticket{attendee_email: nil} ->
        :ok

      %Ticket{gs1_identifier: nil} ->
        :ok

      ticket ->
        qr_png = GS1.qr_png(ticket.gs1_identifier.digital_link)

        with {:ok, _email} <- TicketNotifier.deliver_ticket(ticket, ticket.event, qr_png) do
          :ok
        end
    end
  end
end
