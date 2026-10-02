defmodule Datem.Repo.Migrations.AddNewVisitorFields do
  use Ecto.Migration

  def change do
    alter table(:visitors) do
      add :id_number, :string
      add :vehicle_reg, :string
      add :purpose, :string
      add :host_employee_id, references(:users, on_delete: :nilify_all)
      add :approved_at, :utc_datetime
      add :denied_at, :utc_datetime
    end

    create index(:visitors, [:host_employee_id])

  end
end
