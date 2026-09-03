defmodule Datem.Repo.Migrations.CreateEvents do
  use Ecto.Migration

  def change do
    create table(:events) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :description, :text
      add :venue, :string
      add :starts_at, :utc_datetime
      add :ends_at, :utc_datetime
      add :status, :string, null: false, default: "draft"
      add :join_link_token, :string

      timestamps(type: :utc_datetime)
    end

    create index(:events, [:organization_id])
    create unique_index(:events, [:join_link_token])
  end
end
