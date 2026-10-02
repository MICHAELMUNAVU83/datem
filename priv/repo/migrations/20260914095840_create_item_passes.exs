defmodule Datem.Repo.Migrations.CreateItemPasses do
  use Ecto.Migration

  def change do
    create table(:item_passes) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :requested_by_id, references(:employees, on_delete: :delete_all), null: false
      add :approver_id, references(:employees, on_delete: :nilify_all)
      add :item_name, :string, null: false
      add :description, :text
      add :returnable, :boolean, null: false, default: true
      add :reason, :text, null: false
      add :status, :string, null: false, default: "pending"
      add :token, :string, null: false
      add :approved_at, :utc_datetime
      add :denied_at, :utc_datetime
      add :returned_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:item_passes, [:organization_id])
    create unique_index(:item_passes, [:token])
  end
end
