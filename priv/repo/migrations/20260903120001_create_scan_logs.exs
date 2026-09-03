defmodule Datem.Repo.Migrations.CreateScanLogs do
  use Ecto.Migration

  def change do
    create table(:scan_logs) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :scan_type_id, references(:scan_types, on_delete: :delete_all), null: false
      add :subject_type, :string, null: false
      add :subject_id, :integer, null: false
      add :result, :string, null: false
      add :message, :string
      add :metadata, :map, null: false, default: %{}
      add :scanned_at, :utc_datetime, null: false
      add :operator_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:scan_logs, [:organization_id])
    create index(:scan_logs, [:scan_type_id])
    create index(:scan_logs, [:scan_type_id, :subject_type, :subject_id, :result])
  end
end
