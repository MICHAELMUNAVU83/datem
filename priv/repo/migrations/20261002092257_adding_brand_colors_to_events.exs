defmodule Datem.Repo.Migrations.AddingBrandColorsToEvents do
  use Ecto.Migration

  def change do
    alter table(:events) do
      add :brand_color_start, :string, default: "#2563eb", null: false
      add :brand_color_end, :string, default: "#1e40af", null: false
    end
  end
end
