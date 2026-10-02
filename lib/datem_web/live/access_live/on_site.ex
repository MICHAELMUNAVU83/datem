defmodule DatemWeb.AccessLive.OnSite do
  @moduledoc """
  Live view of everyone and every vehicle currently on-site, updating in
  real time from access scans, plus operational alerts (overdue visitors,
  sites at capacity, recent denials).
  """
  use DatemWeb, :live_view

  alias Datem.Access
  alias Datem.Tenancy
  alias Datem.NairobiTime

  @tick_interval :timer.seconds(30)

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if connected?(socket) do
      Phoenix.PubSub.subscribe(
        Datem.PubSub,
        Access.access_logs_topic(Tenancy.organization_id!(scope))
      )

      Process.send_after(self(), :tick, @tick_interval)
    end

    {:ok,
     socket
     |> assign(:recent_denials, [])
     |> assign(:now, DateTime.utc_now())
     |> assign_onsite()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} max_width="max-w-full">
      <.pass_header
        icon="hero-users"
        title="On-site now"
        subtitle={"#{length(@onsite)} currently checked in"}
      />

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

      <div class="mt-6 w-full overflow-hidden rounded-lg border border-zinc-200">
        <table class="w-full table-fixed divide-y divide-zinc-200 text-sm">
          <thead class="bg-zinc-50 text-left text-xs font-medium uppercase tracking-wide text-zinc-500">
            <tr>
              <th class="w-1/4 px-4 py-2">Name</th>
              <th class="w-1/5 px-4 py-2">Host</th>
              <th class="w-1/5 px-4 py-2">Access point</th>
              <th class="w-[15%] px-4 py-2">Time in</th>
              <th class="w-[15%] px-4 py-2">On-site for</th>
              <th class="w-[15%] px-4 py-2"></th>
            </tr>
          </thead>
          <tbody class="divide-y divide-zinc-100 bg-white">
            <tr
              :for={entry <- @onsite}
              class={[
                "align-middle",
                overdue?(entry, @overdue_ids) &&
                  "border-l-4 border-l-amber-400 bg-amber-50/60"
              ]}
            >
              <td class="px-4 py-3 font-medium text-zinc-900">
                {entry.name}
                <span
                  :if={Map.get(entry, :vehicle)}
                  class="ml-2 inline-flex items-center gap-1 rounded-full bg-zinc-100 px-2 py-0.5 text-xs font-normal text-zinc-600"
                >
                  <.icon name="hero-truck" class="size-3" /> {entry.vehicle.plate}
                </span>
              </td>
              <td class="px-4 py-3 text-zinc-600">{entry.host}</td>
              <td class="px-4 py-3 text-zinc-600">{entry.log.access_point.name}</td>
              <td class="px-4 py-3 text-zinc-600">
                {NairobiTime.format(entry.log.scanned_at, "%d %b, %H:%M")}
              </td>
              <td class="px-4 py-3">
                <span class={[
                  "font-medium",
                  overdue?(entry, @overdue_ids) && "text-amber-700"
                ]}>
                  {format_duration(entry.log.scanned_at, @now)}
                </span>
              </td>

              <td class="px-4 py-3">
                <.button
                  :if={entry.kind == :visitor}
                  variant="secondary"
                  phx-click="manual_checkout"
                  phx-value-pass-id={entry.log.subject_id}
                  phx-value-access-point-id={entry.log.access_point_id}
                  data-confirm={"Check out #{entry.name}?"}
                >
                  Check out
                </.button>
              </td>
            </tr>
            <tr :if={@onsite == []}>
              <td colspan="5" class="px-4 py-6 text-center text-zinc-500">
                No one is on-site right now.
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("manual_checkout", %{"pass-id" => pass_id, "access-point-id" => ap_id}, socket) do
    scope = socket.assigns.current_scope
    pass = Access.get_visitor_pass_for_scope!(scope, pass_id)
    access_point = Access.get_access_point_for_scope!(scope, ap_id)

    case Access.manual_check_out_pass(scope, pass, access_point, scope.user) do
      {:ok, _log} -> {:noreply, put_flash(socket, :info, "#{pass.visitor.name} checked out.")}
      {:error, reason} -> {:noreply, put_flash(socket, :error, "Couldn't check out: #{reason}")}
    end
  end

  @impl true
  def handle_info({:access_log_created, _log}, socket), do: {:noreply, assign_onsite(socket)}

  def handle_info({:access_denied, denial}, socket) do
    {:noreply, update(socket, :recent_denials, &Enum.take([denial | &1], 5))}
  end

  def handle_info(:tick, socket) do
    Process.send_after(self(), :tick, @tick_interval)
    {:noreply, assign(socket, :now, DateTime.utc_now())}
  end

  defp assign_onsite(socket) do
    scope = socket.assigns.current_scope
    alerts = Access.list_alerts(scope)

    onsite =
      scope
      |> Access.list_onsite()
      |> Enum.sort_by(& &1.log.scanned_at, DateTime)

    overdue_ids =
      alerts
      |> Enum.filter(&(&1.type == :overdue))
      |> MapSet.new(& &1.entry.log.id)

    socket
    |> assign(:onsite, onsite)
    |> assign(:alerts, alerts)
    |> assign(:overdue_ids, overdue_ids)
  end

  defp overdue?(entry, overdue_ids), do: MapSet.member?(overdue_ids, entry.log.id)

  defp format_duration(scanned_at, now) do
    diff = DateTime.diff(now, scanned_at, :second)
    hours = div(diff, 3600)
    minutes = div(rem(diff, 3600), 60)

    if hours > 0, do: "#{hours}h #{minutes}m", else: "#{minutes}m"
  end

  defp alert_message(%{type: :overdue, entry: entry}) do
    "#{entry.name} has been on-site since #{NairobiTime.format(entry.log.scanned_at, "%H:%M")} — check in on them"
  end

  defp alert_message(%{type: :capacity} = alert) do
    "#{alert.site_name} is at capacity (#{alert.onsite_count}/#{alert.capacity})"
  end
end
