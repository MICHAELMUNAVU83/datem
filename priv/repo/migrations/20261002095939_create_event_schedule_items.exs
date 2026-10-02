defmodule Datem.Repo.Migrations.CreateEventScheduleItems do
  use Ecto.Migration

  def change do
    create table(:event_schedule_items) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :event_id, references(:events, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :description, :string
      add :location, :string
      add :day_label, :string
      add :starts_at, :utc_datetime, null: false
      add :ends_at, :utc_datetime
      add :position, :integer, null: false, default: 0
      add :is_active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create index(:event_schedule_items, [:organization_id])
    create index(:event_schedule_items, [:event_id])
    create index(:event_schedule_items, [:event_id, :starts_at])
  end
end
