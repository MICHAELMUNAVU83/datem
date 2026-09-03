defmodule Datem.Access.Vehicle do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(active revoked)

  schema "vehicles" do
    field :plate, :string
    field :make, :string
    field :model, :string
    field :status, :string, default: "active"

    belongs_to :organization, Datem.Organizations.Organization
    belongs_to :visitor, Datem.Access.Visitor
    belongs_to :gs1_identifier, Datem.GS1.Identifier

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  @doc false
  def changeset(vehicle, attrs) do
    vehicle
    |> cast(attrs, [:plate, :make, :model, :organization_id, :visitor_id])
    |> validate_required([:plate, :organization_id])
    |> update_change(:plate, &String.upcase/1)
    |> validate_length(:plate, max: 20)
    |> unique_constraint([:organization_id, :plate])
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:visitor_id)
  end

  @doc false
  def gs1_identifier_changeset(vehicle, gs1_identifier_id) do
    change(vehicle, gs1_identifier_id: gs1_identifier_id)
  end
end
