defmodule Datem.GS1.Identifier do
  @moduledoc """
  The registry of every GS1 identifier ever issued: the central lookup
  used to resolve a scanned Digital Link back to the entity it names.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @kinds [:gln, :gsrn, :giai]

  schema "gs1_identifiers" do
    field :kind, Ecto.Enum, values: @kinds
    field :value, :string
    field :ai, :string
    field :digital_link, :string
    field :subject_type, :string
    field :subject_id, :string
    field :interoperable, :boolean, default: true

    belongs_to :organization, Datem.Organizations.Organization

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(identifier, attrs) do
    identifier
    |> cast(attrs, [
      :organization_id,
      :kind,
      :value,
      :ai,
      :digital_link,
      :subject_type,
      :subject_id,
      :interoperable
    ])
    |> validate_required([
      :organization_id,
      :kind,
      :value,
      :ai,
      :digital_link,
      :subject_type,
      :subject_id
    ])
    |> unique_constraint(:value)
  end
end
