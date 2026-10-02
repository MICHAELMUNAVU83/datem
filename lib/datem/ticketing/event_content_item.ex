defmodule Datem.Ticketing.EventContentItem do
  @moduledoc """
  One piece of extra content shown on an event's public ticket page —
  a banner image or an external link (programme, photo gallery, etc.).
  Ordered by `position`; only `is_active` items are shown publicly.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(banner link)

  schema "event_content_items" do
    field :title, :string
    field :kind, :string, default: "link"
    field :url, :string
    field :position, :integer, default: 0
    field :is_active, :boolean, default: true

    belongs_to :organization, Datem.Organizations.Organization
    belongs_to :event, Datem.Ticketing.Event

    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds

  def admin_kind_options, do: [{"Link", "link"}, {"Banner image", "banner"}]

 @doc false
def changeset(item, attrs) do
  item
  |> cast(attrs, [:title, :kind, :url, :position, :is_active, :organization_id, :event_id])
  |> validate_required([:title, :kind, :url, :organization_id, :event_id])
  |> validate_inclusion(:kind, @kinds)
  |> validate_length(:title, max: 160)
  |> update_change(:url, &normalize_url/1)
  |> validate_format(:url, ~r/^https?:\/\/.+/, message: "must be a valid URL")
  |> foreign_key_constraint(:organization_id)
  |> foreign_key_constraint(:event_id)
end

defp normalize_url(nil), do: nil

defp normalize_url(url) do
  trimmed = String.trim(url)

  if String.match?(trimmed, ~r/^https?:\/\//) do
    trimmed
  else
    "https://" <> trimmed
  end
end
end
