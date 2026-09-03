defmodule Datem.Repo.Migrations.CreateOrganizations do
  use Ecto.Migration

  def change do
    create table(:organizations) do
      add :name, :string, null: false
      add :slug, :string, null: false
      add :gs1_company_prefix, :string
      add :plan, :string, null: false, default: "free"
      add :settings, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:organizations, [:slug])
  end
end
