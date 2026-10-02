defmodule Datem.Ticketing.EventScheduleItem do
  @moduledoc """
  One session or block on an event's programme. Events can span multiple days;
  items are ordered by `starts_at` then `position`. Only `is_active` items are
  shown on the public ticket page.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "event_schedule_items" do
    field :title, :string
    field :description, :string
    field :location, :string
    field :day_label, :string
    field :starts_at, :utc_datetime
    field :ends_at, :utc_datetime
    field :position, :integer, default: 0
    field :is_active, :boolean, default: true

    belongs_to :organization, Datem.Organizations.Organization
    belongs_to :event, Datem.Ticketing.Event

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(item, attrs) do
    item
    |> cast(attrs, [
      :title,
      :description,
      :location,
      :day_label,
      :starts_at,
      :ends_at,
      :position,
      :is_active,
      :organization_id,
      :event_id
    ])
    |> validate_required([:title, :starts_at, :organization_id, :event_id])
    |> validate_length(:title, max: 160)
    |> validate_length(:description, max: 1000)
    |> validate_length(:location, max: 160)
    |> validate_length(:day_label, max: 80)
    |> validate_starts_before_ends()
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:event_id)
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
