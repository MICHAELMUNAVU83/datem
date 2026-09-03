defmodule Datem.Access.VisitorPass do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(active expired revoked)

  schema "visitor_passes" do
    field :valid_from, :utc_datetime
    field :valid_to, :utc_datetime
    field :status, :string, default: "active"

    belongs_to :organization, Datem.Organizations.Organization
    belongs_to :visitor, Datem.Access.Visitor
    belongs_to :gs1_identifier, Datem.GS1.Identifier

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  @doc false
  def changeset(visitor_pass, attrs) do
    visitor_pass
    |> cast(attrs, [:valid_from, :valid_to, :organization_id, :visitor_id, :gs1_identifier_id])
    |> validate_required([
      :valid_from,
      :valid_to,
      :organization_id,
      :visitor_id,
      :gs1_identifier_id
    ])
    |> validate_valid_window()
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:visitor_id)
    |> foreign_key_constraint(:gs1_identifier_id)
  end

  @doc false
  def revoke_changeset(visitor_pass) do
    change(visitor_pass, status: "revoked")
  end

  defp validate_valid_window(changeset) do
    from = get_field(changeset, :valid_from)
    to = get_field(changeset, :valid_to)

    if from && to && DateTime.compare(from, to) != :lt do
      add_error(changeset, :valid_to, "must be after the valid-from time")
    else
      changeset
    end
  end
end
