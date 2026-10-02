defmodule Datem.Repo.Migrations.AddHeadToEmployees do
  use Ecto.Migration

  def change do
    alter table(:employees) do
      add :head_employee_id, references(:employees, on_delete: :nilify_all)
    end

    create index(:employees, [:head_employee_id])
  end
end
