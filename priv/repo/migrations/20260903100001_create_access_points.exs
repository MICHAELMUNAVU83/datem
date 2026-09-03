defmodule Datem.Repo.Migrations.CreateAccessPoints do
  use Ecto.Migration

  def change do
    create table(:access_points) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :site_id, references(:sites, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :gln, :string
      add :direction_rules, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:access_points, [:organization_id])
    create index(:access_points, [:site_id])
  end
end
