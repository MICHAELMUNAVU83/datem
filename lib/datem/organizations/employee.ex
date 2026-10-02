defmodule Datem.Organizations.Employee do
  use Ecto.Schema
  import Ecto.Changeset

  schema "employees" do
    field :name, :string
    field :email, :string
    field :phone, :string
    field :department, :string

    belongs_to :organization, Datem.Organizations.Organization
    belongs_to :user, Datem.Accounts.User
    belongs_to :head_employee, Datem.Organizations.Employee

    timestamps(type: :utc_datetime)
  end

  @doc false
def changeset(employee, attrs) do
  employee
  |> cast(attrs, [:name, :email, :phone, :department, :organization_id, :user_id, :head_employee_id])
  |> validate_required([:name, :organization_id])
  |> validate_length(:name, max: 160)
  |> foreign_key_constraint(:organization_id)
  |> foreign_key_constraint(:user_id)
  |> foreign_key_constraint(:head_employee_id)
end
end
