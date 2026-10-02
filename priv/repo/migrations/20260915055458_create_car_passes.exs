defmodule Datem.Repo.Migrations.CreateCarPasses do
  use Ecto.Migration

  def change do
    create table(:car_passes) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :vehicle_id, references(:vehicles, on_delete: :nilify_all)
      add :requested_by_id, references(:employees, on_delete: :delete_all), null: false
      add :approver_id, references(:employees, on_delete: :nilify_all)
      add :serial, :string, null: false
      add :carrying, :string
      add :reason, :text, null: false
      add :date_out, :utc_datetime
      add :date_in, :utc_datetime
      add :mileage_out, :integer
      add :mileage_in, :integer
      add :status, :string, null: false, default: "pending"
      add :decision_reason, :text
      add :token, :string, null: false
      add :approved_at, :utc_datetime
      add :denied_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:car_passes, [:organization_id])
    create unique_index(:car_passes, [:token])
    create unique_index(:car_passes, [:organization_id, :serial])
  end
end
