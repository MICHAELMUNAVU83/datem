defmodule Datem.Ticketing.TicketScan do
  use Ecto.Schema
  import Ecto.Changeset

  schema "ticket_scans" do
    field :direction, :string
    field :scanned_at, :utc_datetime

    belongs_to :organization, Datem.Organizations.Organization
    belongs_to :event, Datem.Ticketing.Event
    belongs_to :ticket, Datem.Ticketing.Ticket
    belongs_to :operator, Datem.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(ticket_scan, attrs) do
    ticket_scan
    |> cast(attrs, [
      :direction,
      :scanned_at,
      :organization_id,
      :event_id,
      :ticket_id,
      :operator_id
    ])
    |> validate_required([:direction, :scanned_at, :organization_id, :event_id, :ticket_id])
    |> validate_inclusion(:direction, ["in", "out"])
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:event_id)
    |> foreign_key_constraint(:ticket_id)
  end
end
