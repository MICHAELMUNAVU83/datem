defmodule Datem.Repo.Migrations.AddFieldToEvents do
  use Ecto.Migration


  def up do
    alter table(:events) do
      add :required_attendee_fields, :json
    end

    execute "UPDATE events SET required_attendee_fields = '[]' WHERE required_attendee_fields IS NULL"

    alter table(:events) do
      modify :required_attendee_fields, :json, null: false
    end
  end

  def down do
    alter table(:events) do
      remove :required_attendee_fields
    end
  end
end
