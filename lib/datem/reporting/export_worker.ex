defmodule Datem.Reporting.ExportWorker do
  @moduledoc """
  Builds a requested CSV export on the `:exports` queue and writes it to
  `Datem.Reporting.exports_dir/0`.

  Enqueued by `Datem.Reporting.request_export/3`. The worker rebuilds the
  caller's scope from the export's own `organization_id` rather than trusting
  anything in the job args, so a job can only ever read the tenant it was
  created for.
  """
  use Oban.Worker, queue: :exports, max_attempts: 3

  alias Datem.Accounts.Scope
  alias Datem.Organizations.Organization
  alias Datem.Repo
  alias Datem.Reporting
  alias Datem.Reporting.{CSV, Export}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"export_id" => export_id}}) do
    case Reporting.get_export(export_id) do
      nil -> :ok
      %Export{status: "completed"} -> :ok
      export -> generate(export)
    end
  end

  defp generate(%Export{} = export) do
    {:ok, export} = Reporting.finish_export(export, "processing")
    scope = %Scope{organization: Repo.get!(Organization, export.organization_id)}

    {headers, rows} = Reporting.export_rows(scope, export.kind, export.filters)
    filename = filename(export)

    path = Path.join([Reporting.exports_dir(), to_string(export.organization_id), filename])
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, CSV.encode(headers, rows))

    {:ok, _export} =
      Reporting.finish_export(export, "completed", %{
        filename: filename,
        row_count: length(rows),
        completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

    :ok
  rescue
    error ->
      # The failure belongs on the row the user is watching, not only in the
      # job table — then re-raise so Oban still records and retries the job.
      Reporting.finish_export(export, "failed", %{error: Exception.message(error)})
      reraise error, __STACKTRACE__
  end

  defp filename(%Export{} = export) do
    stamp = Calendar.strftime(export.inserted_at, "%Y%m%d-%H%M%S")
    "#{export.kind}-#{stamp}-#{export.id}.csv"
  end
end
