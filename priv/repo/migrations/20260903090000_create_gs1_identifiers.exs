defmodule Datem.Repo.Migrations.CreateGs1Identifiers do
  use Ecto.Migration

  def change do
    create table(:gs1_identifiers) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :kind, :string, null: false
      add :value, :string, null: false
      add :ai, :string, null: false
      add :digital_link, :string, null: false
      add :subject_type, :string, null: false
      add :subject_id, :string, null: false
      add :interoperable, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create unique_index(:gs1_identifiers, [:value])
    create index(:gs1_identifiers, [:organization_id])
    create index(:gs1_identifiers, [:organization_id, :subject_type, :subject_id])
  end
end
