defmodule DatemWeb.AccessLive.OnSite do
  @moduledoc """
  Live view of everyone and every vehicle currently on-site, updating in
  real time from access scans, plus operational alerts (overdue visitors,
  sites at capacity, recent denials).
  """
  use DatemWeb, :live_view

  alias Datem.Access
  alias Datem.Tenancy

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if connected?(socket) do
      Phoenix.PubSub.subscribe(
        Datem.PubSub,
        Access.access_logs_topic(Tenancy.organization_id!(scope))
      )
    end

    {:ok,
     socket
     |> assign(:recent_denials, [])
     |> assign_onsite()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        On-site now
        <:subtitle>{length(@onsite)} currently checked in</:subtitle>
      </.header>

      <div :if={@alerts != [] or @recent_denials != []} class="mt-4 space-y-2">
        <div
          :for={alert <- @alerts}
          class="flex items-center gap-2 rounded-lg border border-amber-200 bg-amber-50 px-4 py-2 text-sm text-amber-800"
        >
          <.icon name="hero-exclamation-triangle" class="size-4 shrink-0" />
          {alert_message(alert)}
        </div>
        <div
          :for={denial <- @recent_denials}
          class="flex items-center gap-2 rounded-lg border border-red-200 bg-red-50 px-4 py-2 text-sm text-red-800"
        >
          <.icon name="hero-x-circle" class="size-4 shrink-0" />
          Denied: {denial.name} at {denial.access_point.name} ({Phoenix.Naming.humanize(denial.reason)})
        </div>
      </div>

      <.table id="onsite" rows={@onsite}>
        <:col :let={entry} label="Name">{entry.name}</:col>
        <:col :let={entry} label="Host">{entry.host}</:col>
        <:col :let={entry} label="Access point">{entry.log.access_point.name}</:col>
        <:col :let={entry} label="Time in">{Calendar.strftime(entry.log.scanned_at, "%H:%M")}</:col>
        <:empty>No one is on-site right now.</:empty>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def handle_info({:access_log_created, _log}, socket), do: {:noreply, assign_onsite(socket)}

  def handle_info({:access_denied, denial}, socket) do
    {:noreply, update(socket, :recent_denials, &Enum.take([denial | &1], 5))}
  end

  defp assign_onsite(socket) do
    scope = socket.assigns.current_scope

    socket
    |> assign(:onsite, Access.list_onsite(scope))
    |> assign(:alerts, Access.list_alerts(scope))
  end

  defp alert_message(%{type: :overdue, entry: entry}) do
    "#{entry.name} has been on-site since #{Calendar.strftime(entry.log.scanned_at, "%H:%M")} — check in on them"
  end

  defp alert_message(%{type: :capacity} = alert) do
    "#{alert.site_name} is at capacity (#{alert.onsite_count}/#{alert.capacity})"
  end
end
