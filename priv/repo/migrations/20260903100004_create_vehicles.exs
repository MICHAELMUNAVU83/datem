defmodule Datem.Repo.Migrations.CreateVehicles do
  use Ecto.Migration

  def change do
    create table(:vehicles) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :visitor_id, references(:visitors, on_delete: :nilify_all)
      add :gs1_identifier_id, references(:gs1_identifiers, on_delete: :nilify_all)
      add :plate, :string, null: false
      add :make, :string
      add :model, :string
      add :status, :string, null: false, default: "active"

      timestamps(type: :utc_datetime)
    end

    create index(:vehicles, [:organization_id])
    create index(:vehicles, [:visitor_id])
    create unique_index(:vehicles, [:organization_id, :plate])
  end
end
