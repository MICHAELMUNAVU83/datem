defmodule Datem.Ticketing.Event do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(draft published closed)
  @attendee_detail_fields ~w(company id_number phone_number gender dob)

  schema "events" do
    field :name, :string
    field :description, :string
    field :venue, :string
    field :starts_at, :utc_datetime
    field :ends_at, :utc_datetime
    field :status, :string, default: "draft"
    field :join_link_token, :string
    field :required_attendee_fields, {:array, :string}, default: []

    field :brand_color_start, :string, default: "#2563eb"
    field :brand_color_end, :string, default: "#1e40af"

    belongs_to :organization, Datem.Organizations.Organization
    has_many :ticket_types, Datem.Ticketing.TicketType
    has_many :tickets, Datem.Ticketing.Ticket

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  @doc false
  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :name,
      :description,
      :venue,
      :starts_at,
      :ends_at,
      :organization_id,
      :required_attendee_fields,
      :brand_color_start,
      :brand_color_end
    ])
    |> validate_required([:name, :organization_id])
    |> validate_length(:name, max: 160)
    |> validate_subset(:required_attendee_fields, @attendee_detail_fields)
    |> validate_format(:brand_color_start, ~r/^#[0-9A-Fa-f]{6}$/,
      message: "must be a hex color like #2563eb"
    )
    |> validate_format(:brand_color_end, ~r/^#[0-9A-Fa-f]{6}$/,
      message: "must be a hex color like #2563eb"
    )
    |> validate_starts_before_ends()
    |> foreign_key_constraint(:organization_id)
  end

  @doc "Sets the shareable public join-link token once generated."
  def join_link_changeset(event, token) do
    event |> change(join_link_token: token) |> unique_constraint(:join_link_token)
  end

  @doc false
  def status_changeset(event, status) when status in @statuses do
    change(event, status: status)
  end

  defp validate_starts_before_ends(changeset) do
    starts_at = get_field(changeset, :starts_at)
    ends_at = get_field(changeset, :ends_at)

    if starts_at && ends_at && DateTime.compare(starts_at, ends_at) != :lt do
      add_error(changeset, :ends_at, "must be after the start time")
    else
      changeset
    end
  end
end
