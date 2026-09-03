defmodule DatemWeb.ExportController do
  @moduledoc """
  Serves completed CSV exports.

  Export files live outside `priv/static` because they are tenant data: the
  only way to reach one is through this controller, which resolves the export
  inside the caller's organisation scope first.
  """
  use DatemWeb, :controller

  alias Datem.Reporting

  def download(conn, %{"id" => id}) do
    export = Reporting.get_export_for_scope!(conn.assigns.current_scope, id)
    path = Reporting.export_path(export)

    if (export.status == "completed" and path) && File.exists?(path) do
      send_download(conn, {:file, path}, filename: export.filename)
    else
      conn
      |> put_flash(:error, "That export isn't ready to download.")
      |> redirect(to: ~p"/exports")
    end
  end
end
