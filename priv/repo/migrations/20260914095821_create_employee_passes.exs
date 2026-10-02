defmodule Datem.Repo.Migrations.CreateEmployeePasses do
  use Ecto.Migration

  def change do
    create table(:employee_passes) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :employee_id, references(:employees, on_delete: :delete_all), null: false
      add :requested_by_id, references(:employees, on_delete: :delete_all), null: false
      add :approver_id, references(:employees, on_delete: :nilify_all)
      add :for_self, :boolean, null: false, default: true
      add :reason, :text, null: false
      add :status, :string, null: false, default: "pending"
      add :token, :string, null: false
      add :approved_at, :utc_datetime
      add :denied_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:employee_passes, [:organization_id])
    create unique_index(:employee_passes, [:token])
  end
end
