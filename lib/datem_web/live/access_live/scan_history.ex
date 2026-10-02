defmodule DatemWeb.AccessLive.ScanHistory do
  @moduledoc "Full audit trail: everyone and every vehicle scanned, when, and where."
  use DatemWeb, :live_view

  on_mount {DatemWeb.UserAuth, {:require_role, [:owner, :admin, :operator]}}

  alias Datem.Access

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :history, Access.list_scan_history(socket.assigns.current_scope))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} max_width="max-w-full">
      <div class="mb-6 overflow-hidden rounded-xl border border-blue-100">
        <.pass_header icon="hero-clock" title="Scan history" subtitle="Every check-in and check-out, across every access point" />

        <.table id="scan-history" rows={@history}>
          <:col :let={e} label="Name">{e.name}</:col>
          <:col :let={e} label="Host">{e.host}</:col>
          <:col :let={e} label="Direction">
            <.badge kind={(e.log.direction == "in" && :success) || :neutral}>{e.log.direction}</.badge>
          </:col>
          <:col :let={e} label="Access point">{e.log.access_point.name}</:col>
          <:col :let={e} label="When">{Calendar.strftime(e.log.scanned_at, "%d %b %Y, %H:%M")}</:col>
          <:empty>No scans recorded yet.</:empty>
        </.table>
      </div>
    </Layouts.app>
    """
  end
end
