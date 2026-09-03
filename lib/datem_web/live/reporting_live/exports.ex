defmodule DatemWeb.ReportingLive.Exports do
  @moduledoc """
  The export queue: every CSV an organisation has requested, its status, and
  a download link once the worker has written the file.

  Exports are an owner/admin action (operators scan, they don't export), and
  the list updates live as `Datem.Reporting.ExportWorker` finishes each job.
  """
  use DatemWeb, :live_view

  on_mount {DatemWeb.UserAuth, {:require_role, [:owner, :admin]}}

  alias Datem.Reporting

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    if connected?(socket), do: Reporting.subscribe_to_exports(scope)

    {:ok, assign_exports(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Exports
        <:subtitle>CSVs are built in the background — download them here when ready</:subtitle>
        <:actions>
          <.button navigate={~p"/reports/access"} variant="secondary">New access export</.button>
        </:actions>
      </.header>

      <.table id="exports" rows={@exports}>
        <:col :let={export} label="Export">{Reporting.export_label(export.kind)}</:col>
        <:col :let={export} label="Requested">
          {Calendar.strftime(export.inserted_at, "%d %b %H:%M")}
        </:col>
        <:col :let={export} label="Rows">{export.row_count}</:col>
        <:col :let={export} label="Status">
          <.badge kind={status_kind(export.status)}>{export.status}</.badge>
          <span :if={export.error} class="ml-2 text-xs text-red-600">{export.error}</span>
        </:col>
        <:action :let={export}>
          <.link
            :if={export.status == "completed"}
            href={~p"/exports/#{export}/download"}
            class="font-medium text-blue-600"
          >
            Download
          </.link>
        </:action>
        <:empty>No exports yet. Request one from a report.</:empty>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def handle_info({:export_updated, _export}, socket), do: {:noreply, assign_exports(socket)}
  def handle_info(_message, socket), do: {:noreply, socket}

  defp assign_exports(socket) do
    assign(socket, :exports, Reporting.list_exports(socket.assigns.current_scope))
  end

  defp status_kind("completed"), do: :success
  defp status_kind("failed"), do: :danger
  defp status_kind(_status), do: :info
end
