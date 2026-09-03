defmodule Datem.Repo.Migrations.CreateAccessLogs do
  use Ecto.Migration

  def change do
    create table(:access_logs) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :access_point_id, references(:access_points, on_delete: :delete_all), null: false
      add :subject_type, :string, null: false
      add :subject_id, :integer, null: false
      add :direction, :string, null: false
      add :scanned_at, :utc_datetime, null: false
      add :operator_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:access_logs, [:organization_id])
    create index(:access_logs, [:access_point_id])
    create index(:access_logs, [:organization_id, :subject_type, :subject_id])
  end
end
