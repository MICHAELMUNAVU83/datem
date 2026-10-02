defmodule DatemWeb.ReportingLive.AccessReport do
  @moduledoc """
  Entries and exits over a time range, broken down by site, access point and
  day, with a one-click CSV export of the same filtered rows.

  Operators can scan but not report or export, so this view is gated to
  owners, admins and viewers.
  """
  use DatemWeb, :live_view

  on_mount {DatemWeb.UserAuth, {:require_role, [:owner, :admin, :viewer]}}

  alias Datem.Access
  alias Datem.Reporting

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    today = Date.utc_today()

    {:ok,
     socket
     |> assign(:sites, Access.list_sites(scope))
     |> assign(:access_points, Access.list_access_points(scope))
     |> assign(:filters, %{
       "from" => Date.to_iso8601(Date.add(today, -7)),
       "to" => Date.to_iso8601(today),
       "site_id" => "",
       "access_point_id" => ""
     })
     |> assign_report()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Access report
        <:subtitle>Entries and exits by site, access point and day</:subtitle>
        <:actions>
          <.button phx-click="export" phx-disable-with="Queueing...">Export CSV</.button>
        </:actions>
      </.header>

      <.form for={%{}} as={:filters} phx-change="filter" id="access-report-filters">
        <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <.input type="date" name="filters[from]" value={@filters["from"]} label="From" />
          <.input type="date" name="filters[to]" value={@filters["to"]} label="To" />
          <.input
            type="select"
            name="filters[site_id]"
            value={@filters["site_id"]}
            label="Site"
            prompt="All sites"
            options={Enum.map(@sites, &{&1.name, &1.id})}
          />
          <.input
            type="select"
            name="filters[access_point_id]"
            value={@filters["access_point_id"]}
            label="Access point"
            prompt="All access points"
            options={Enum.map(@access_points, &{"#{&1.site.name} · #{&1.name}", &1.id})}
          />
        </div>
      </.form>

      <div class="mt-2 grid gap-4 sm:grid-cols-3">
        <.stat_card label="Entries" value={@report.totals.entries} icon="hero-arrow-right-circle" />
        <.stat_card label="Exits" value={@report.totals.exits} icon="hero-arrow-left-circle" />
        <.stat_card
          label="Unique people & vehicles"
          value={@report.totals.unique_subjects}
          icon="hero-identification"
        />
      </div>

      <div class="mt-6 grid gap-6 lg:grid-cols-2">
        <.card title="By site">
          <.table id="report-by-site" rows={@report.by_site}>
            <:col :let={row} label="Site">{row.name}</:col>
            <:col :let={row} label="Entries">{row.entries}</:col>
            <:col :let={row} label="Exits">{row.exits}</:col>
            <:empty>No scans in this range.</:empty>
          </.table>
        </.card>

        <.card title="By access point">
          <.table id="report-by-access-point" rows={@report.by_access_point}>
            <:col :let={row} label="Access point">{row.site_name} · {row.name}</:col>
            <:col :let={row} label="Entries">{row.entries}</:col>
            <:col :let={row} label="Exits">{row.exits}</:col>
            <:empty>No scans in this range.</:empty>
          </.table>
        </.card>
      </div>

      <.card title="By day" class="mt-6">
        <.table id="report-by-day" rows={@report.by_day}>
          <:col :let={row} label="Day">{format_day(row.day)}</:col>
          <:col :let={row} label="Entries">{row.entries}</:col>
          <:col :let={row} label="Exits">{row.exits}</:col>
          <:empty>No scans in this range.</:empty>
        </.table>
      </.card>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("filter", %{"filters" => filters}, socket) do
    {:noreply, socket |> assign(:filters, filters) |> assign_report()}
  end

  def handle_event("export", _params, socket) do
    case Reporting.request_export(
           socket.assigns.current_scope,
           "access_logs",
           socket.assigns.filters
         ) do
      {:ok, _export} ->
        {:noreply,
         socket
         |> put_flash(:info, "Export queued — it will appear under Exports when ready.")
         |> push_navigate(to: ~p"/exports")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not queue that export.")}
    end
  end

  defp assign_report(socket) do
    assign(
      socket,
      :report,
      Reporting.access_report(socket.assigns.current_scope, socket.assigns.filters)
    )
  end
@nairobi_offset_seconds 3 * 60 * 60

defp to_nairobi(%DateTime{} = dt), do: DateTime.add(dt, @nairobi_offset_seconds, :second)
defp to_nairobi(%NaiveDateTime{} = ndt), do: NaiveDateTime.add(ndt, @nairobi_offset_seconds, :second)


defp format_day(%Date{} = day), do: Calendar.strftime(day, "%a %d %b")
defp format_day(%DateTime{} = day), do: day |> to_nairobi() |> Calendar.strftime("%a %d %b")
defp format_day(%NaiveDateTime{} = day), do: day |> to_nairobi() |> Calendar.strftime("%a %d %b")
end
