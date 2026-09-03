defmodule Datem.Scanning.ScanLog do
  @moduledoc """
  The audit trail for the shared scanning engine: one row per scan attempt at
  a `scan_type`, whatever the outcome.

  Unlike `access_logs`, denials are persisted too — the result of a scan is
  itself the record operators and reports care about.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @results ~w(accepted duplicate expired denied)
  @subject_types ~w(ticket visitor_pass vehicle)

  schema "scan_logs" do
    field :subject_type, :string
    field :subject_id, :integer
    field :result, :string
    field :message, :string
    field :metadata, :map, default: %{}
    field :scanned_at, :utc_datetime

    belongs_to :organization, Datem.Organizations.Organization
    belongs_to :scan_type, Datem.Scanning.ScanType
    belongs_to :operator, Datem.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def results, do: @results
  def subject_types, do: @subject_types

  @doc false
  def changeset(scan_log, attrs) do
    scan_log
    |> cast(attrs, [
      :subject_type,
      :subject_id,
      :result,
      :message,
      :metadata,
      :scanned_at,
      :organization_id,
      :scan_type_id,
      :operator_id
    ])
    |> validate_required([
      :subject_type,
      :subject_id,
      :result,
      :scanned_at,
      :organization_id,
      :scan_type_id
    ])
    |> validate_inclusion(:result, @results)
    |> validate_inclusion(:subject_type, @subject_types)
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:scan_type_id)
  end
end
