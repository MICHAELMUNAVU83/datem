defmodule Datem.Repo.Migrations.AddCapacityToSites do
  use Ecto.Migration

  def change do
    alter table(:sites) do
      add :capacity, :integer
    end
  end
end
