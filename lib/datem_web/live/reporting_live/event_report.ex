defmodule DatemWeb.ReportingLive.EventReport do
  @moduledoc """
  Attendance for one event: registered vs checked-in, the same split per
  ticket type, and the accepted-scan tally for every checkpoint on the event.

  Same role gate as the access report — operators scan, they don't report.
  """
  use DatemWeb, :live_view

  on_mount {DatemWeb.UserAuth, {:require_role, [:owner, :admin, :viewer]}}

  alias Datem.Reporting
  alias Datem.Scanning
  alias Datem.Ticketing

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    if connected?(socket), do: Scanning.subscribe(scope)

    {:ok, assign(socket, :events, Ticketing.list_events(scope))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, assign_report(socket, params["id"] || default_event_id(socket))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Event report
        <:subtitle>Attendance, check-in rate and scan-type breakdown</:subtitle>
        <:actions>
          <.button :if={@report} phx-click="export" phx-disable-with="Queueing...">
            Export attendees
          </.button>
        </:actions>
      </.header>

      <.form for={%{}} as={:event} phx-change="select_event" id="event-report-picker">
        <.input
          type="select"
          name="event[id]"
          value={@report && @report.event.id}
          label="Event"
          prompt="Choose an event"
          options={Enum.map(@events, &{&1.name, &1.id})}
        />
      </.form>

      <div
        :if={!@report}
        class="rounded-lg border border-dashed border-gray-200 bg-white py-12 text-center"
      >
        <p class="text-sm text-gray-500">Pick an event to see its attendance.</p>
      </div>

      <div :if={@report}>
        <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <.stat_card label="Registered" value={@report.registered} icon="hero-ticket" />
          <.stat_card label="Checked in" value={@report.checked_in} icon="hero-check-circle" />
          <.stat_card label="Check-in rate" value={"#{@report.check_in_rate}%"} />
          <.stat_card label="Cancelled" value={@report.cancelled} icon="hero-x-circle" />
        </div>

        <div class="mt-6 grid gap-6 lg:grid-cols-2">
          <.card title="By ticket type">
            <.table id="event-report-ticket-types" rows={@report.by_ticket_type}>
              <:col :let={row} label="Ticket type">{row.name}</:col>
              <:col :let={row} label="Checked in">{row.checked_in} / {row.registered}</:col>
              <:col :let={row} label="Rate">{row.check_in_rate}%</:col>
              <:empty>No registrations yet.</:empty>
            </.table>
          </.card>

          <.card title="Checkpoints">
            <:actions>
              <.link phx-click="export_tallies" class="text-sm font-medium text-blue-600">
                Export tallies
              </.link>
            </:actions>
            <.table id="event-report-scan-types" rows={@report.scan_types}>
              <:col :let={tally} label="Checkpoint">{tally.scan_type.name}</:col>
              <:col :let={tally} label="Claimed">
                {tally.claimed}{if tally.eligible, do: " / #{tally.eligible}"}
              </:col>
              <:col :let={tally} label="Share">
                {Reporting.percentage(tally.claimed, tally.eligible || 0)}%
              </:col>
              <:empty>No checkpoints configured for this event.</:empty>
            </.table>
          </.card>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("select_event", %{"event" => %{"id" => id}}, socket) do
    {:noreply, push_patch(socket, to: ~p"/reports/events?#{[id: id]}")}
  end

  def handle_event("export", _params, socket),
    do: {:noreply, queue_export(socket, "attendees")}

  def handle_event("export_tallies", _params, socket),
    do: {:noreply, queue_export(socket, "scan_tallies")}

  @impl true
  def handle_info({:scan_logged, _log}, socket) do
    {:noreply, assign_report(socket, socket.assigns.report && socket.assigns.report.event.id)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp queue_export(socket, kind) do
    scope = socket.assigns.current_scope
    filters = %{"event_id" => socket.assigns.report.event.id}

    case Reporting.request_export(scope, kind, filters) do
      {:ok, _export} ->
        socket
        |> put_flash(:info, "Export queued — it will appear under Exports when ready.")
        |> push_navigate(to: ~p"/exports")

      {:error, _reason} ->
        put_flash(socket, :error, "Could not queue that export.")
    end
  end

  defp assign_report(socket, nil), do: assign(socket, :report, nil)
  defp assign_report(socket, ""), do: assign(socket, :report, nil)

  defp assign_report(socket, event_id) do
    scope = socket.assigns.current_scope
    event = Ticketing.get_event_for_scope!(scope, event_id)

    assign(socket, :report, Reporting.event_report(scope, event))
  end

  defp default_event_id(%{assigns: %{events: [event | _]}}), do: event.id
  defp default_event_id(_socket), do: nil
end
