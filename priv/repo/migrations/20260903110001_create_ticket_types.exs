defmodule Datem.Repo.Migrations.CreateTicketTypes do
  use Ecto.Migration

  def change do
    create table(:ticket_types) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :event_id, references(:events, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :price, :decimal, null: false, default: 0
      add :quantity, :integer
      add :per_attendee_limit, :integer, null: false, default: 1

      timestamps(type: :utc_datetime)
    end

    create index(:ticket_types, [:organization_id])
    create index(:ticket_types, [:event_id])
  end
end
