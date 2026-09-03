defmodule Datem.Repo.Migrations.CreateSites do
  use Ecto.Migration

  def change do
    create table(:sites) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :address, :string
      add :gln, :string

      timestamps(type: :utc_datetime)
    end

    create index(:sites, [:organization_id])
  end
end
