defmodule Datem.Access.AccessLog do
  use Ecto.Schema
  import Ecto.Changeset

  @directions ~w(in out)

  schema "access_logs" do
    field :subject_type, :string
    field :subject_id, :integer
    field :direction, :string
    field :scanned_at, :utc_datetime

    belongs_to :organization, Datem.Organizations.Organization
    belongs_to :access_point, Datem.Access.AccessPoint
    belongs_to :operator, Datem.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def directions, do: @directions

  @doc false
  def changeset(access_log, attrs) do
    access_log
    |> cast(attrs, [
      :subject_type,
      :subject_id,
      :direction,
      :scanned_at,
      :organization_id,
      :access_point_id,
      :operator_id
    ])
    |> validate_required([
      :subject_type,
      :subject_id,
      :direction,
      :scanned_at,
      :organization_id,
      :access_point_id
    ])
    |> validate_inclusion(:direction, @directions)
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:access_point_id)
  end
end
