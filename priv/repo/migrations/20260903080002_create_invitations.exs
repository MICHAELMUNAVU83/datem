defmodule Datem.Repo.Migrations.CreateInvitations do
  use Ecto.Migration

  def change do
  create table(:invitations) do
  add :email, :string, null: false
  add :role, :string, null: false
  add :token_hash, :binary, null: false, size: 32
  add :status, :string, null: false, default: "pending"
  add :expires_at, :utc_datetime, null: false
  add :accepted_at, :utc_datetime
  add :organization_id, references(:organizations, on_delete: :delete_all), null: false
  add :invited_by_id, references(:users, on_delete: :nilify_all)

  timestamps(type: :utc_datetime)
end

create unique_index(:invitations, [:token_hash])
create index(:invitations, [:organization_id])

execute """
ALTER TABLE invitations
ADD COLUMN pending_email VARCHAR(255)
  GENERATED ALWAYS AS (CASE WHEN status = 'pending' THEN email ELSE NULL END) STORED
""", "ALTER TABLE invitations DROP COLUMN pending_email"

create unique_index(:invitations, [:organization_id, :pending_email],
  name: :invitations_org_email_pending_index
)



  end
end
