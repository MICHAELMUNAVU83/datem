defmodule Datem.Ticketing.Ticket do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(registered checked_in checked_out cancelled)

@attendee_detail_fields ~w(company id_number phone_number gender dob)

schema "tickets" do
  field :attendee_name, :string
  field :attendee_email, :string
  field :company, :string
  field :id_number, :string
  field :phone_number, :string
  field :gender, :string
  field :dob, :date
  field :status, :string, default: "registered"

  belongs_to :organization, Datem.Organizations.Organization
  belongs_to :event, Datem.Ticketing.Event
  belongs_to :ticket_type, Datem.Ticketing.TicketType
  belongs_to :gs1_identifier, Datem.GS1.Identifier

  timestamps(type: :utc_datetime)
end

def attendee_detail_fields, do: @attendee_detail_fields

@doc """
Changeset for registering/editing an attendee. `required_fields` is the
event's `required_attendee_fields` list — any of `company`, `id_number`,
`phone_number`, `gender`, `dob` named there become required on top of the
always-required name/org/event/ticket-type.
"""
def changeset(ticket, attrs, required_fields \\ []) do
  extra_required =
    required_fields
    |> Enum.filter(&(&1 in @attendee_detail_fields))
    |> Enum.map(&String.to_existing_atom/1)

  ticket
  |> cast(attrs, [
    :attendee_name,
    :attendee_email,
    :company,
    :id_number,
    :phone_number,
    :gender,
    :dob,
    :organization_id,
    :event_id,
    :ticket_type_id
  ])
  |> validate_required(
    [:attendee_name, :organization_id, :event_id, :ticket_type_id] ++ extra_required
  )
  |> validate_length(:attendee_name, max: 160)
  |> foreign_key_constraint(:organization_id)
  |> foreign_key_constraint(:event_id)
  |> foreign_key_constraint(:ticket_type_id)
end

  def statuses, do: @statuses


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
