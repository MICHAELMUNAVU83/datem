defmodule Datem.Repo.Migrations.AddAttendeeInformation do
  use Ecto.Migration

    def change do
    alter table(:tickets) do
      add :company, :string
      add :id_number, :string
      add :phone_number, :string
      add :gender, :string
      add :dob, :date
    end
  end
end
