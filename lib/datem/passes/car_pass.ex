defmodule Datem.Passes.CarPass do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending approved denied out returned)

  schema "car_passes" do
    field :serial, :string
    field :carrying, :string
    field :reason, :string
    field :date_out, :utc_datetime
    field :date_in, :utc_datetime
    field :mileage_out, :integer
    field :mileage_in, :integer
    field :status, :string, default: "pending"
    field :decision_reason, :string
    field :token, :string
    field :approved_at, :utc_datetime
    field :denied_at, :utc_datetime

    belongs_to :organization, Datem.Organizations.Organization
    belongs_to :vehicle, Datem.Access.Vehicle
    belongs_to :requested_by, Datem.Organizations.Employee
    belongs_to :approver, Datem.Organizations.Employee

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  def changeset(pass, attrs) do
    pass
    |> cast(attrs, [:serial, :carrying, :reason, :date_out, :vehicle_id, :requested_by_id, :approver_id, :organization_id])
    |> validate_required([:serial, :reason, :requested_by_id, :organization_id])
    |> foreign_key_constraint(:vehicle_id)
    |> foreign_key_constraint(:requested_by_id)
    |> foreign_key_constraint(:organization_id)
    |> unique_constraint([:organization_id, :serial])
  end

  def decision_changeset(pass, "approved", _reason) do
    change(pass, status: "approved", approved_at: DateTime.utc_now() |> DateTime.truncate(:second))
  end

  def decision_changeset(pass, "denied", reason) do
    change(pass, status: "denied", denied_at: DateTime.utc_now() |> DateTime.truncate(:second), decision_reason: reason)
  end

  def depart_changeset(pass, mileage_out) do
    change(pass, status: "out", date_out: DateTime.utc_now() |> DateTime.truncate(:second), mileage_out: mileage_out)
  end

  def return_changeset(pass, mileage_in) do
    change(pass, status: "returned", date_in: DateTime.utc_now() |> DateTime.truncate(:second), mileage_in: mileage_in)
  end
end
