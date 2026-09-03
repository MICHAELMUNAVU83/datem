defmodule Datem.Access.Visitor do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending registered checked_in checked_out denied)

  schema "visitors" do
    field :name, :string
    field :contact, :string
    field :company, :string
    field :host, :string
    field :photo_path, :string
    field :status, :string, default: "pending"
    field :invite_token, :string

    belongs_to :organization, Datem.Organizations.Organization
    has_many :visitor_passes, Datem.Access.VisitorPass

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  @doc "Changeset used by staff registering a walk-in visitor directly."
  def changeset(visitor, attrs) do
    visitor
    |> cast(attrs, [:name, :contact, :company, :host, :organization_id])
    |> validate_required([:name, :organization_id])
    |> validate_length(:name, max: 160)
    |> foreign_key_constraint(:organization_id)
  end

  @doc "Creates the placeholder record behind a pre-registration link, before the visitor has filled in their own details."
  def pre_registration_changeset(visitor, attrs) do
    visitor
    |> cast(attrs, [:host, :organization_id, :invite_token])
    |> validate_required([:host, :organization_id, :invite_token])
    |> put_change(:status, "pending")
    |> unique_constraint(:invite_token)
    |> foreign_key_constraint(:organization_id)
  end

  @doc "Changeset the visitor themselves submits via the public pre-registration link."
  def self_registration_changeset(visitor, attrs) do
    visitor
    |> cast(attrs, [:name, :contact, :company])
    |> validate_required([:name, :contact])
    |> validate_length(:name, max: 160)
    |> put_change(:status, "registered")
  end

  @doc false
  def photo_changeset(visitor, photo_path) do
    change(visitor, photo_path: photo_path)
  end

  @doc false
  def status_changeset(visitor, status) when status in @statuses do
    change(visitor, status: status)
  end
end
