defmodule Datem.Ticketing.TicketType do
  use Ecto.Schema
  import Ecto.Changeset

  schema "ticket_types" do
    field :name, :string
    field :price, :decimal, default: Decimal.new(0)
    field :quantity, :integer
    field :per_attendee_limit, :integer, default: 1

    belongs_to :organization, Datem.Organizations.Organization
    belongs_to :event, Datem.Ticketing.Event
    has_many :tickets, Datem.Ticketing.Ticket

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(ticket_type, attrs) do
    ticket_type
    |> cast(attrs, [:name, :price, :quantity, :per_attendee_limit, :organization_id, :event_id])
    |> validate_required([:name, :organization_id, :event_id])
    |> validate_length(:name, max: 160)
    |> validate_number(:price, greater_than_or_equal_to: 0)
    |> validate_number(:quantity, greater_than: 0)
    |> validate_number(:per_attendee_limit, greater_than: 0)
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:event_id)
  end
end
