defmodule Datem.Repo.Migrations.AddFieldsToEmployeePasses do
  use Ecto.Migration


  def change do
    alter table(:employee_passes) do
      add :expected_departure_at, :utc_datetime
         add :expected_return_at, :utc_datetime
      add :decision_reason, :text
    end
  end

end
