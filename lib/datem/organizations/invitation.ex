defmodule Datem.Organizations.Invitation do
  use Ecto.Schema
  import Ecto.Changeset

  @invitable_roles [:admin, :operator, :viewer]
  @validity_in_days 7

  schema "invitations" do
    field :email, :string
    field :role, Ecto.Enum, values: @invitable_roles
    field :token_hash, :binary, redact: true
    field :status, Ecto.Enum, values: [:pending, :accepted, :revoked], default: :pending
    field :expires_at, :utc_datetime
    field :accepted_at, :utc_datetime

    belongs_to :organization, Datem.Organizations.Organization
    belongs_to :invited_by, Datem.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def invitable_roles, do: @invitable_roles

  @doc """
  Builds an invitation, returning the raw (unhashed) token to deliver by
  email alongside the record to insert. The database only ever stores the
  hash, mirroring `Datem.Accounts.UserToken`.
  """
  def build(organization, invited_by, attrs) do
    {raw_token, hashed_token} = build_token()

    changeset =
      %__MODULE__{}
      |> cast(attrs, [:email, :role])
      |> put_change(:organization_id, organization.id)
      |> put_change(:invited_by_id, invited_by && invited_by.id)
      |> put_change(:token_hash, hashed_token)
      |> put_change(
        :expires_at,
        DateTime.utc_now(:second) |> DateTime.add(@validity_in_days, :day)
      )
      |> validate_required([:email, :role, :organization_id, :token_hash, :expires_at])
      |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
        message: "must have the @ sign and no spaces"
      )
      |> foreign_key_constraint(:organization_id)
      |> unique_constraint(:email,
        name: :invitations_org_email_pending_index,
        message: "already has a pending invitation"
      )

    {raw_token, changeset}
  end

  def accept_changeset(invitation) do
    change(invitation, status: :accepted, accepted_at: DateTime.utc_now(:second))
  end

  def revoke_changeset(invitation) do
    change(invitation, status: :revoked)
  end

  def expired?(%__MODULE__{expires_at: expires_at}) do
    DateTime.after?(DateTime.utc_now(), expires_at)
  end

  defp build_token do
    raw = :crypto.strong_rand_bytes(32)
    {Base.url_encode64(raw, padding: false), :crypto.hash(:sha256, raw)}
  end
end
