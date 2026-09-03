defmodule Datem.Repo.Migrations.CreateExports do
  use Ecto.Migration

  def change do
    create table(:exports) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :requested_by_id, references(:users, on_delete: :nilify_all)
      add :kind, :string, null: false
      add :filters, :map, null: false, default: %{}
      add :status, :string, null: false, default: "pending"
      add :filename, :string
      add :row_count, :integer
      add :error, :string
      add :completed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:exports, [:organization_id])
    create index(:exports, [:organization_id, :inserted_at])
  end
end
