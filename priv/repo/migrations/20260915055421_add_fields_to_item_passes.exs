defmodule Datem.Repo.Migrations.AddFieldsToItemPasses do
  use Ecto.Migration


  def change do
    alter table(:item_passes) do
      add :decision_reason, :text
    end
  end
end
