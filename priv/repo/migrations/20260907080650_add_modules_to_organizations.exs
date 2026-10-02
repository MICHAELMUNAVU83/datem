defmodule Datem.Repo.Migrations.AddModulesToOrganizations do
  use Ecto.Migration

  def up do
    alter table(:organizations) do
      add :modules, :json
    end

    execute "UPDATE organizations SET modules = '[\"access\"]' WHERE modules IS NULL"

    alter table(:organizations) do
      modify :modules, :json, null: false
    end
  end

  def down do
    alter table(:organizations) do
      remove :modules
    end
  end
end
