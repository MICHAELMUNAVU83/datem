defmodule Datem.Repo.Migrations.AddPlatformAdminToUsers do
  use Ecto.Migration

  def change do
   alter table(:users) do
      add :platform_admin, :boolean, default: false, null: false
    end
  end
end
