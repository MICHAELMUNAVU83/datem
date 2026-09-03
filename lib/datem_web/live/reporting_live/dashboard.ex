defmodule DatemWeb.ReportingLive.Dashboard do
  @moduledoc """
  The organisation's home dashboard: who is on-site today, which events are
  running, and what has recently been turned away — all updating live from
  the access and scanning topics.
  """
  use DatemWeb, :live_view

  alias Datem.Access
  alias Datem.Reporting
  alias Datem.Scanning
  alias Datem.Tenancy

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if connected?(socket) do
      Phoenix.PubSub.subscribe(
        Datem.PubSub,
        Access.access_logs_topic(Tenancy.organization_id!(scope))
      )

      Scanning.subscribe(scope)
    end

    {:ok, assign_dashboard(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Today
        <:subtitle>Live across every site and event in {org_name(@current_scope)}</:subtitle>
        <:actions>
          <.button navigate={~p"/reports/access"} variant="secondary">Reports</.button>
        </:actions>
      </.header>

      <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <.stat_card label="On-site now" value={@dashboard.onsite_count} icon="hero-users" />
        <.stat_card
          label="Visitors today"
          value={@dashboard.visitors_today}
          hint="scanned in since midnight"
          icon="hero-arrow-right-on-rectangle"
        />
        <.stat_card
          label="Active events"
          value={length(@dashboard.active_events)}
          icon="hero-ticket"
        />
        <.stat_card
          label="Recent denials"
          value={length(@dashboard.recent_denials)}
          hint="last 10 scan results"
          icon="hero-shield-exclamation"
        />
      </div>

      <div
        :for={alert <- @dashboard.alerts}
        class="mt-4 flex items-center gap-2 rounded-lg border border-amber-200 bg-amber-50 px-4 py-2 text-sm text-amber-800"
      >
        <.icon name="hero-exclamation-triangle" class="size-4 shrink-0" />
        {alert_message(alert)}
      </div>

      <div class="mt-6 grid gap-6 lg:grid-cols-2">
        <.card title="On-site now">
          <:actions>
            <.link navigate={~p"/onsite"} class="text-sm font-medium text-blue-600">View all</.link>
          </:actions>
          <.table id="dashboard-onsite" rows={Enum.take(@dashboard.onsite, 8)}>
            <:col :let={entry} label="Name">{entry.name}</:col>
            <:col :let={entry} label="Host">{entry.host}</:col>
            <:col :let={entry} label="Since">
              {Calendar.strftime(entry.log.scanned_at, "%H:%M")}
            </:col>
            <:empty>No one is on-site right now.</:empty>
          </.table>
        </.card>

        <.card title="Active events">
          <.table id="dashboard-events" rows={@dashboard.active_events}>
            <:col :let={row} label="Event">
              <.link navigate={~p"/events/#{row.event}"} class="font-medium text-blue-600">
                {row.event.name}
              </.link>
            </:col>
            <:col :let={row} label="Checked in">{row.checked_in} / {row.registered}</:col>
            <:col :let={row} label="Rate">
              {Reporting.percentage(row.checked_in, row.registered)}%
            </:col>
            <:empty>No events are running right now.</:empty>
          </.table>
        </.card>
      </div>

      <.card title="Recent denials" class="mt-6">
        <.table id="dashboard-denials" rows={@dashboard.recent_denials}>
          <:col :let={log} label="Time">{Calendar.strftime(log.scanned_at, "%H:%M")}</:col>
          <:col :let={log} label="Checkpoint">{log.scan_type.name}</:col>
          <:col :let={log} label="Subject">{subject_label(log)}</:col>
          <:col :let={log} label="Result">
            <.badge kind={result_kind(log.result)}>{log.result}</.badge>
          </:col>
          <:col :let={log} label="Reason">{log.message}</:col>
          <:empty>Nothing has been turned away.</:empty>
        </.table>
      </.card>
    </Layouts.app>
    """
  end

  @impl true
  def handle_info({:access_log_created, _log}, socket), do: {:noreply, assign_dashboard(socket)}
  def handle_info({:scan_logged, _log}, socket), do: {:noreply, assign_dashboard(socket)}
  def handle_info(_message, socket), do: {:noreply, socket}

  defp assign_dashboard(socket) do
    assign(socket, :dashboard, Reporting.dashboard(socket.assigns.current_scope))
  end

  defp subject_label(%{metadata: %{"label" => label}}) when is_binary(label), do: label
  defp subject_label(log), do: Phoenix.Naming.humanize(log.subject_type)

  defp result_kind("duplicate"), do: :warning
  defp result_kind("expired"), do: :warning
  defp result_kind(_result), do: :danger

  defp org_name(%{organization: %{name: name}}), do: name
  defp org_name(_scope), do: "your organisation"

  defp alert_message(%{type: :overdue, entry: entry}) do
    "#{entry.name} has been on-site since #{Calendar.strftime(entry.log.scanned_at, "%H:%M")} — check in on them"
  end

  defp alert_message(%{type: :capacity} = alert) do
    "#{alert.site_name} is at capacity (#{alert.onsite_count}/#{alert.capacity})"
  end
end
