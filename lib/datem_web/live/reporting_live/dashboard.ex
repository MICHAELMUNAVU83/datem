defmodule DatemWeb.ReportingLive.Dashboard do
  @moduledoc """
  The organisation's home dashboard: who is on-site today, which events are
  running, and what has recently been turned away — all updating live from
  the access and scanning topics. Sections are shown according to the
  modules (access / ticketing) the organisation has.
  """
  use DatemWeb, :live_view

  alias Datem.Access
  alias Datem.Organizations
  alias Datem.Reporting
  alias Datem.Scanning
  alias Datem.Tenancy



  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    has_access = Organizations.has_module?(scope, :access)
    has_ticketing = Organizations.has_module?(scope, :ticketing)

    if connected?(socket) do
      if has_access do
        Phoenix.PubSub.subscribe(
          Datem.PubSub,
          Access.access_logs_topic(Tenancy.organization_id!(scope))
        )
      end

      if has_ticketing, do: Scanning.subscribe(scope)
    end

    modules =
  [access: has_access, ticketing: has_ticketing]
  |> Enum.filter(&elem(&1, 1))
  |> Keyword.keys()

{:ok,
 socket
 |> assign(:has_access, has_access)
 |> assign(:has_ticketing, has_ticketing)
 |> assign(:modules, modules)
 |> assign_dashboard()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Today
        <:subtitle>Live across every site and event in {org_name(@current_scope)}</:subtitle>
        <:actions>
          <span class="inline-flex items-center gap-1.5 rounded-full bg-emerald-50 px-2.5 py-1 text-xs font-medium text-emerald-700 ring-1 ring-inset ring-emerald-200">
            <span class="relative flex size-2">
              <span class="absolute inline-flex h-full w-full animate-ping rounded-full bg-emerald-400 opacity-75">
              </span>
              <span class="relative inline-flex size-2 rounded-full bg-emerald-500"></span>
            </span>
            Live
          </span>
          <.button :if={@has_access} navigate={~p"/reports/access"} variant="secondary">
            Access report
          </.button>
          <.button :if={@has_ticketing} navigate={~p"/reports/events"} variant="secondary">
            Event report
          </.button>
        </:actions>
      </.header>

      <%!-- Stats --%>
      <div class={["grid gap-4 sm:grid-cols-2", @has_access && @has_ticketing && "lg:grid-cols-4"]}>
        <.stat_tile
          :if={@has_access}
          label="On-site now"
          value={@dashboard.onsite_count}
          hint="people currently inside"
          icon="hero-users"
          tone={:blue}
        />
        <.stat_tile
          :if={@has_access}
          label="Visitors today"
          value={@dashboard.visitors_today}
          hint="scanned in since midnight"
          icon="hero-arrow-right-on-rectangle"
          tone={:emerald}
        />
        <.stat_tile
          :if={@has_ticketing}
          label="Active events"
          value={length(@dashboard.active_events)}
          hint="running right now"
          icon="hero-ticket"
          tone={:violet}
        />
        <.stat_tile
          :if={@has_ticketing}
          label="Recent denials"
          value={length(@dashboard.recent_denials)}
          hint="last 10 scan results"
          icon="hero-shield-exclamation"
          tone={if @dashboard.recent_denials == [], do: :gray, else: :rose}
        />
      </div>

      <%!-- Alerts (access only) --%>
      <div :if={@has_access && @dashboard.alerts != []} class="mt-4 space-y-2">
        <div
          :for={alert <- @dashboard.alerts}
          class="flex items-center gap-3 rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900"
        >
          <span class="flex size-8 shrink-0 items-center justify-center rounded-lg bg-amber-100 text-amber-600">
            <.icon name={alert_icon(alert)} class="size-4" />
          </span>
          {alert_message(alert)}
        </div>
      </div>

      <%!-- Main panels --%>
      <div class={["mt-6 grid gap-6", @has_access && @has_ticketing && "lg:grid-cols-2"]}>
        <.card :if={@has_access} title="On-site now">
          <:actions>
            <.link
              navigate={~p"/onsite"}
              class="inline-flex items-center gap-1 text-sm font-medium text-blue-600 hover:text-blue-700"
            >
              View all <.icon name="hero-arrow-right" class="size-3.5" />
            </.link>
          </:actions>
          <.table id="dashboard-onsite" rows={Enum.take(@dashboard.onsite, 8)}>
            <:col :let={entry} label="Name">
              <span class="font-medium text-gray-900">{entry.name}</span>
            </:col>
            <:col :let={entry} label="Host">{entry.host}</:col>
            <:col :let={entry} label="Since">
              <span class="tabular-nums text-gray-500">
                {Calendar.strftime(entry.log.scanned_at, "%H:%M")}
              </span>
            </:col>
            <:empty>No one is on-site right now.</:empty>
          </.table>
        </.card>

        <.card :if={@has_ticketing} title="Active events">
          <:actions>
            <.link
              navigate={~p"/events"}
              class="inline-flex items-center gap-1 text-sm font-medium text-blue-600 hover:text-blue-700"
            >
              View all <.icon name="hero-arrow-right" class="size-3.5" />
            </.link>
          </:actions>
          <.table id="dashboard-events" rows={@dashboard.active_events}>
            <:col :let={row} label="Event">
              <.link
                navigate={~p"/events/#{row.event}"}
                class="font-medium text-blue-600 hover:text-blue-700"
              >
                {row.event.name}
              </.link>
            </:col>
            <:col :let={row} label="Checked in">
              <span class="tabular-nums">{row.checked_in} / {row.registered}</span>
            </:col>
            <:col :let={row} label="Rate">
              <.rate_bar percent={Reporting.percentage(row.checked_in, row.registered)} />
            </:col>
            <:empty>No events are running right now.</:empty>
          </.table>
        </.card>
      </div>

      <%!-- Denials (ticketing only) --%>
      <.card :if={@has_ticketing} title="Recent denials" class="mt-6">
        <.table id="dashboard-denials" rows={@dashboard.recent_denials}>
          <:col :let={log} label="Time">
            <span class="tabular-nums text-gray-500">
              {Calendar.strftime(log.scanned_at, "%H:%M")}
            </span>
          </:col>
          <:col :let={log} label="Checkpoint">{log.scan_type.name}</:col>
          <:col :let={log} label="Subject">{subject_label(log)}</:col>
          <:col :let={log} label="Result">
            <.badge kind={result_kind(log.result)}>{log.result}</.badge>
          </:col>
          <:col :let={log} label="Reason"><span class="text-gray-500">{log.message}</span></:col>
          <:empty>Nothing has been turned away.</:empty>
        </.table>
      </.card>
    </Layouts.app>
    """
  end

  # ── Local components ───────────────────────────────────────────────

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :hint, :string, default: nil
  attr :icon, :string, required: true
  attr :tone, :atom, default: :blue

  defp stat_tile(assigns) do
    ~H"""
    <div class="rounded-xl border border-gray-200 bg-white p-5 shadow-sm transition hover:shadow-md">
      <div class="flex items-center justify-between">
        <p class="text-sm font-medium text-gray-500">{@label}</p>
        <span class={["flex size-9 items-center justify-center rounded-lg", tone_classes(@tone)]}>
          <.icon name={@icon} class="size-5" />
        </span>
      </div>
      <p class="mt-3 text-3xl font-semibold tracking-tight tabular-nums text-gray-900">
        {@value}
      </p>
      <p class="mt-1 h-4 text-xs text-gray-400">{@hint}</p>
    </div>
    """
  end

attr :percent, :integer, required: true

defp rate_bar(assigns) do
  assigns = assign(assigns, :pct, assigns.percent |> min(100) |> max(0))

  ~H"""
  <div class="flex items-center gap-2">
    <div class="h-1.5 w-20 overflow-hidden rounded-full bg-gray-100">
      <div class="h-full rounded-full bg-violet-500" style={"width: #{@pct}%"}></div>
    </div>
    <span class="text-xs tabular-nums text-gray-500">{@percent}%</span>
  </div>
  """
end

  @impl true
  def handle_info({:access_log_created, _log}, socket), do: {:noreply, assign_dashboard(socket)}
  def handle_info({:scan_logged, _log}, socket), do: {:noreply, assign_dashboard(socket)}
  def handle_info(_message, socket), do: {:noreply, socket}

  # ── Helpers ────────────────────────────────────────────────────────

  defp assign_dashboard(socket) do
    assign(socket, :dashboard, Reporting.dashboard(socket.assigns.current_scope))
  end

  defp tone_classes(:blue), do: "bg-blue-50 text-blue-600"
  defp tone_classes(:emerald), do: "bg-emerald-50 text-emerald-600"
  defp tone_classes(:violet), do: "bg-violet-50 text-violet-600"
  defp tone_classes(:rose), do: "bg-rose-50 text-rose-600"
  defp tone_classes(_), do: "bg-gray-100 text-gray-500"

  defp to_number(n) when is_number(n), do: n

  defp to_number(%Decimal{} = d), do: Decimal.to_float(d)

  defp to_number(_), do: 0

  defp subject_label(%{metadata: %{"label" => label}}) when is_binary(label), do: label
  defp subject_label(log), do: Phoenix.Naming.humanize(log.subject_type)

  defp result_kind("duplicate"), do: :warning
  defp result_kind("expired"), do: :warning
  defp result_kind(_result), do: :danger

  defp org_name(%{organization: %{name: name}}), do: name
  defp org_name(_scope), do: "your organisation"

  defp alert_icon(%{type: :overdue}), do: "hero-clock"
  defp alert_icon(_), do: "hero-exclamation-triangle"

  defp alert_message(%{type: :overdue, entry: entry}) do
    "#{entry.name} has been on-site since #{Calendar.strftime(entry.log.scanned_at, "%H:%M")} — check in on them"
  end

  defp assign_dashboard(socket) do
  %{current_scope: scope, modules: modules} = socket.assigns
  assign(socket, :dashboard, Reporting.dashboard(scope, nil, modules))
end
  defp alert_message(%{type: :capacity} = alert) do
    "#{alert.site_name} is at capacity (#{alert.onsite_count}/#{alert.capacity})"
  end
end
