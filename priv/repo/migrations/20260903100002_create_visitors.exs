defmodule Datem.Repo.Migrations.CreateVisitors do
  use Ecto.Migration

  def change do
    create table(:visitors) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :name, :string
      add :contact, :string
      add :company, :string
      add :host, :string
      add :photo_path, :string
      add :status, :string, null: false, default: "pending"
      add :invite_token, :string

      timestamps(type: :utc_datetime)
    end

    create index(:visitors, [:organization_id])
    create unique_index(:visitors, [:invite_token])
  end
end
