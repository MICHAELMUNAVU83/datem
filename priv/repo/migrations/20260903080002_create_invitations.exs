defmodule Datem.Repo.Migrations.CreateInvitations do
  use Ecto.Migration

  def change do
    create table(:invitations) do
      add :email, :citext, null: false
      add :role, :string, null: false
      add :token_hash, :binary, null: false
      add :status, :string, null: false, default: "pending"
      add :expires_at, :utc_datetime, null: false
      add :accepted_at, :utc_datetime
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :invited_by_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:invitations, [:token_hash])
    create index(:invitations, [:organization_id])

    create unique_index(:invitations, [:organization_id, :email],
             where: "status = 'pending'",
             name: :invitations_org_email_pending_index
           )
  end
end
