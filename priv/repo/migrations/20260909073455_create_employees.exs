defmodule Datem.Repo.Migrations.CreateEmployees do
  use Ecto.Migration

  def change do
    create table(:employees) do
      add :name, :string, null: false
      add :email, :string
      add :phone, :string
      add :department, :string
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:employees, [:organization_id])
    create index(:employees, [:user_id])
  end
end
