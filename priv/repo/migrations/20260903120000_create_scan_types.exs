defmodule Datem.Repo.Migrations.CreateScanTypes do
  use Ecto.Migration

  def change do
    create table(:scan_types) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :event_id, references(:events, on_delete: :delete_all)
      add :site_id, references(:sites, on_delete: :delete_all)
      add :name, :string, null: false
      add :rules, :map, null: false, default: %{}
      add :active_from, :utc_datetime
      add :active_to, :utc_datetime
      add :active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create index(:scan_types, [:organization_id])
    create index(:scan_types, [:event_id])
    create index(:scan_types, [:site_id])

    create constraint(:scan_types, :scan_types_exactly_one_scope,
             check: "(event_id is null) != (site_id is null)"
           )
  end
end
