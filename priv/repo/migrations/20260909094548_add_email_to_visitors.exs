defmodule Datem.Repo.Migrations.AddEmailToVisitors do
  use Ecto.Migration

  def change do
    alter table(:visitors) do
      add :email, :string
    end
  end
end
