defmodule Datem.Organizations.Organization do
  use Ecto.Schema
  import Ecto.Changeset

  schema "organizations" do
    field :name, :string
    field :slug, :string
    field :gs1_company_prefix, :string
    field :plan, :string, default: "free"
    field :settings, :map, default: %{}
    field :modules, {:array, :string}, default: ["access"]

    has_many :memberships, Datem.Organizations.Membership
    has_many :invitations, Datem.Organizations.Invitation

    timestamps(type: :utc_datetime)
  end

  @doc false
def changeset(organization, attrs) do
  organization
  |> cast(attrs, [:name, :slug, :gs1_company_prefix, :plan, :settings, :modules])
  |> validate_required([:name, :slug])
  |> validate_length(:name, max: 160)
  |> validate_format(:slug, ~r/^[a-z0-9]+(-[a-z0-9]+)*$/,
    message: "must contain only lowercase letters, numbers, and hyphens"
  )
  |> validate_subset(:modules, ["access", "ticketing"])
  |> unique_constraint(:slug)
end

  @doc "Changeset for updates made through the organisation settings UI."
  def settings_changeset(organization, attrs) do
    organization
    |> cast(attrs, [:name, :gs1_company_prefix])
    |> validate_required([:name])
    |> validate_length(:name, max: 160)
    |> update_change(:gs1_company_prefix, fn
      nil -> nil
      prefix -> prefix |> String.trim() |> normalize_blank()
    end)
    |> validate_change(:gs1_company_prefix, fn :gs1_company_prefix, prefix ->
      if is_nil(prefix) or String.match?(prefix, ~r/^\d{6,10}$/) do
        []
      else
        [gs1_company_prefix: "must be 6 to 10 digits, as licensed from GS1"]
      end
    end)
  end

  defp normalize_blank(""), do: nil
  defp normalize_blank(value), do: value
end
