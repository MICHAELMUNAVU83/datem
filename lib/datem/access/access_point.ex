defmodule Datem.Access.AccessPoint do
  use Ecto.Schema
  import Ecto.Changeset

  schema "access_points" do
    field :name, :string
    field :gln, :string
    field :direction_rules, :map, default: %{}

    belongs_to :organization, Datem.Organizations.Organization
    belongs_to :site, Datem.Access.Site

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(access_point, attrs) do
    access_point
    |> cast(attrs, [:name, :direction_rules, :organization_id, :site_id])
    |> validate_required([:name, :organization_id, :site_id])
    |> validate_length(:name, max: 160)
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:site_id)
  end

  @doc "Sets the GLN extension once it has been issued by the GS1 identity engine."
  def gln_changeset(access_point, gln) do
    change(access_point, gln: gln)
  end
end
