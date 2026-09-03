defmodule Datem.Organizations.Membership do
  use Ecto.Schema
  import Ecto.Changeset

  @roles [:owner, :admin, :operator, :viewer]

  schema "memberships" do
    field :role, Ecto.Enum, values: @roles

    belongs_to :user, Datem.Accounts.User
    belongs_to :organization, Datem.Organizations.Organization

    timestamps(type: :utc_datetime)
  end

  def roles, do: @roles

  @doc false
  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:role, :user_id, :organization_id])
    |> validate_required([:role, :user_id, :organization_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:organization_id)
    |> unique_constraint([:user_id, :organization_id])
  end
end
