defmodule Datem.Repo.Migrations.AddObanJobsTable do
  use Ecto.Migration

  def up, do: Oban.Migrations.up(prefix: false)

  def down, do: Oban.Migrations.down(prefix: false)
end
