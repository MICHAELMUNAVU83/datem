defmodule Datem.Ticketing.Ticket do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(registered checked_in checked_out cancelled)

  schema "tickets" do
    field :attendee_name, :string
    field :attendee_email, :string
    field :status, :string, default: "registered"

    belongs_to :organization, Datem.Organizations.Organization
    belongs_to :event, Datem.Ticketing.Event
    belongs_to :ticket_type, Datem.Ticketing.TicketType
    belongs_to :gs1_identifier, Datem.GS1.Identifier

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  @doc false
  def changeset(ticket, attrs) do
    ticket
    |> cast(attrs, [:attendee_name, :attendee_email, :organization_id, :event_id, :ticket_type_id])
    |> validate_required([:attendee_name, :organization_id, :event_id, :ticket_type_id])
    |> validate_length(:attendee_name, max: 160)
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:event_id)
    |> foreign_key_constraint(:ticket_type_id)
  end

  @doc "Attaches the GSRN identifier once it has been issued by the GS1 identity engine."
  def gs1_identifier_changeset(ticket, gs1_identifier_id) do
    ticket
    |> change(gs1_identifier_id: gs1_identifier_id)
    |> foreign_key_constraint(:gs1_identifier_id)
  end

  @doc false
  def status_changeset(ticket, status) when status in @statuses do
    change(ticket, status: status)
  end
end
