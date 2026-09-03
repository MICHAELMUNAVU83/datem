defmodule Datem.Repo.Migrations.CreateTicketScans do
  use Ecto.Migration

  def change do
    create table(:ticket_scans) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :event_id, references(:events, on_delete: :delete_all), null: false
      add :ticket_id, references(:tickets, on_delete: :delete_all), null: false
      add :direction, :string, null: false
      add :scanned_at, :utc_datetime, null: false
      add :operator_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:ticket_scans, [:organization_id])
    create index(:ticket_scans, [:event_id])
    create index(:ticket_scans, [:ticket_id])
  end
end
