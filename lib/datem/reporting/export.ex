defmodule Datem.Reporting.Export do
  @moduledoc """
  A requested CSV export and its lifecycle.

  Exports are generated off the request cycle by
  `Datem.Reporting.ExportWorker`, so the row here is both the job's input
  (kind + filters) and the record the user downloads from once it is
  `completed`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(access_logs attendees scan_tallies)
  @statuses ~w(pending processing completed failed)

  schema "exports" do
    field :kind, :string
    field :filters, :map, default: %{}
    field :status, :string, default: "pending"
    field :filename, :string
    field :row_count, :integer
    field :error, :string
    field :completed_at, :utc_datetime

    belongs_to :organization, Datem.Organizations.Organization
    belongs_to :requested_by, Datem.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds
  def statuses, do: @statuses

  @doc false
  def changeset(export, attrs) do
    export
    |> cast(attrs, [:kind, :filters, :organization_id, :requested_by_id])
    |> validate_required([:kind, :organization_id])
    |> validate_inclusion(:kind, @kinds)
    |> foreign_key_constraint(:organization_id)
  end

  @doc false
  def status_changeset(export, status, attrs \\ %{}) when status in @statuses do
    export
    |> cast(attrs, [:filename, :row_count, :error, :completed_at])
    |> put_change(:status, status)
  end
end
