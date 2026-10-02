defmodule Datem.Repo.Migrations.CreateEventTicketContents do
  use Ecto.Migration


  def change do
    create table(:event_content_items) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :event_id, references(:events, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :kind, :string, null: false, default: "link"
      add :url, :string, null: false
      add :position, :integer, null: false, default: 0
      add :is_active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create index(:event_content_items, [:organization_id])
    create index(:event_content_items, [:event_id])
  end
end
