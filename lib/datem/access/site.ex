defmodule Datem.Access.Site do
  use Ecto.Schema
  import Ecto.Changeset

  schema "sites" do
    field :name, :string
    field :address, :string
    field :gln, :string
    field :capacity, :integer

    belongs_to :organization, Datem.Organizations.Organization
    has_many :access_points, Datem.Access.AccessPoint

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(site, attrs) do
    site
    |> cast(attrs, [:name, :address, :capacity, :organization_id])
    |> validate_required([:name, :organization_id])
    |> validate_length(:name, max: 160)
    |> validate_number(:capacity, greater_than: 0)
    |> foreign_key_constraint(:organization_id)
  end

  @doc "Sets the GLN once it has been issued by the GS1 identity engine."
  def gln_changeset(site, gln) do
    change(site, gln: gln)
  end
end
