defmodule Datem.Repo.Migrations.CreateTickets do
  use Ecto.Migration

  def change do
    create table(:tickets) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :event_id, references(:events, on_delete: :delete_all), null: false
      add :ticket_type_id, references(:ticket_types, on_delete: :delete_all), null: false
      add :gs1_identifier_id, references(:gs1_identifiers, on_delete: :nilify_all)
      add :attendee_name, :string, null: false
      add :attendee_email, :string
      add :status, :string, null: false, default: "registered"

      timestamps(type: :utc_datetime)
    end

    create index(:tickets, [:organization_id])
    create index(:tickets, [:event_id])
    create index(:tickets, [:ticket_type_id])
  end
end
