defmodule Datem.Passes.EmployeePass do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending approved denied)

  schema "employee_passes" do
    field :for_self, :boolean, default: true
    field :reason, :string
    field :status, :string, default: "pending"
    field :token, :string
    field :approved_at, :utc_datetime
    field :denied_at, :utc_datetime
    field :expected_departure_at, :utc_datetime
field :expected_return_at, :utc_datetime
field :decision_reason, :string

    belongs_to :organization, Datem.Organizations.Organization
    belongs_to :employee, Datem.Organizations.Employee
    belongs_to :requested_by, Datem.Organizations.Employee
    belongs_to :approver, Datem.Organizations.Employee

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

def changeset(pass, attrs) do
  pass
  |> cast(attrs, [:for_self, :reason, :expected_departure_at, :expected_return_at, :employee_id, :requested_by_id, :approver_id, :organization_id])
  |> validate_required([:reason, :employee_id, :requested_by_id, :organization_id])
  |> foreign_key_constraint(:employee_id)
  |> foreign_key_constraint(:requested_by_id)
  |> foreign_key_constraint(:organization_id)
end

def decision_changeset(pass, "approved", _reason) do
  change(pass, status: "approved", approved_at: DateTime.utc_now() |> DateTime.truncate(:second))
end

def decision_changeset(pass, "denied", reason) do
  change(pass, status: "denied", denied_at: DateTime.utc_now() |> DateTime.truncate(:second), decision_reason: reason)
end
end
