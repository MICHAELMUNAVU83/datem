defmodule Datem.Repo.Migrations.CreateVisitorPasses do
  use Ecto.Migration

  def change do
    create table(:visitor_passes) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :visitor_id, references(:visitors, on_delete: :delete_all), null: false
      add :gs1_identifier_id, references(:gs1_identifiers, on_delete: :nilify_all)
      add :valid_from, :utc_datetime, null: false
      add :valid_to, :utc_datetime, null: false
      add :status, :string, null: false, default: "active"

      timestamps(type: :utc_datetime)
    end

    create index(:visitor_passes, [:organization_id])
    create index(:visitor_passes, [:visitor_id])
  end
end
