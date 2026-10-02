defmodule Datem.Access.Visitor do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending awaiting_approval registered denied checked_in checked_out)
  @email_regex ~r/^[^\s]+@[^\s]+\.[^\s]+$/

  schema "visitors" do
    field :name, :string
    field :contact, :string
    field :email, :string
    field :company, :string
    field :host, :string
    field :photo_path, :string
    field :status, :string, default: "pending"
    field :invite_token, :string

    field :id_number, :string
    field :vehicle_reg, :string
    field :purpose, :string
    field :approved_at, :utc_datetime
    field :denied_at, :utc_datetime

    belongs_to :host_employee, Datem.Organizations.Employee, foreign_key: :host_employee_id
    belongs_to :organization, Datem.Organizations.Organization
    has_many :visitor_passes, Datem.Access.VisitorPass

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  def changeset(visitor, attrs) do
    visitor
    |> cast(attrs, [:name, :contact, :email, :company, :host, :organization_id, :id_number, :vehicle_reg, :purpose, :host_employee_id, :approved_at, :denied_at])
    |> validate_required([:name, :organization_id])
    |> validate_length(:name, max: 160)
    |> validate_format(:email, @email_regex, message: "must be a valid email")
    |> foreign_key_constraint(:organization_id)
  end

  @doc "Changeset for a visitor registering themselves from the public landing page."
  def public_registration_changeset(visitor, attrs) do
    visitor
    |> cast(attrs, [
      :name,
      :contact,
      :email,
      :company,
      :id_number,
      :vehicle_reg,
      :purpose,
      :host_employee_id,
      :organization_id
    ])
    |> validate_required([:name, :contact, :email, :organization_id, :host_employee_id])
    |> validate_length(:name, max: 160)
    |> validate_format(:email, @email_regex, message: "must be a valid email")
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:host_employee_id)
  end

  def pre_registration_changeset(visitor, attrs) do
    visitor
    |> cast(attrs, [:host, :host_employee_id, :organization_id, :invite_token])
    |> validate_required([:host, :organization_id, :invite_token])
    |> put_change(:status, "pending")
    |> unique_constraint(:invite_token)
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:host_employee_id)
  end

  @doc "Changeset for updating who a returning visitor is here to see, e.g. when renewing an expired pass."
def host_changeset(visitor, attrs) do
  visitor
  |> cast(attrs, [:host, :host_employee_id, :purpose])
  |> foreign_key_constraint(:host_employee_id)
end

  def self_registration_changeset(visitor, attrs) do
    visitor
    |> cast(attrs, [:name, :contact, :email, :company, :id_number, :vehicle_reg, :purpose])
    |> validate_required([:name, :contact, :email])
    |> validate_length(:name, max: 160)
    |> validate_format(:email, @email_regex, message: "must be a valid email")
  end

  def photo_changeset(visitor, photo_path), do: change(visitor, photo_path: photo_path)

  def status_changeset(visitor, status) when status in @statuses,
    do: change(visitor, status: status)
end
