defmodule Datem.Passes.ItemPass do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending approved denied)

  schema "item_passes" do
    field :item_name, :string
    field :description, :string
    field :returnable, :boolean, default: true
    field :reason, :string
    field :status, :string, default: "pending"
    field :token, :string
    field :approved_at, :utc_datetime
    field :denied_at, :utc_datetime
    field :returned_at, :utc_datetime

    belongs_to :organization, Datem.Organizations.Organization
    belongs_to :requested_by, Datem.Organizations.Employee
    belongs_to :approver, Datem.Organizations.Employee

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  def changeset(pass, attrs) do
    pass
    |> cast(attrs, [:item_name, :description, :returnable, :reason, :requested_by_id, :approver_id, :organization_id])
    |> validate_required([:item_name, :reason, :requested_by_id, :organization_id])
    |> foreign_key_constraint(:requested_by_id)
    |> foreign_key_constraint(:organization_id)
  end

  def decision_changeset(pass, "approved") do
    change(pass, status: "approved", approved_at: DateTime.utc_now() |> DateTime.truncate(:second))
  end

  def decision_changeset(pass, "denied") do
    change(pass, status: "denied", denied_at: DateTime.utc_now() |> DateTime.truncate(:second))
  end

  def return_changeset(pass) do
    change(pass, returned_at: DateTime.utc_now() |> DateTime.truncate(:second))
  end
end
