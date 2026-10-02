defmodule DatemWeb.AccessLive.VisitorShow do
  use DatemWeb, :live_view

  on_mount {DatemWeb.UserAuth, {:require_role, [:owner, :admin, :operator]}}

  alias Datem.Access
  alias Datem.GS1

  @impl true
def render(assigns) do
  ~H"""
  <Layouts.app flash={@flash} current_scope={@current_scope} max_width="max-w-full">
    <.pass_header icon="hero-identification" title={@visitor.name} subtitle={@visitor.company}>
      <.link navigate={~p"/visitors"} class="text-sm text-gray-600 hover:text-gray-900">
        Back to visitors
      </.link>
    </.pass_header>

    <.card :if={@pass} title="Visitor pass" class="mt-6">
      <div class="flex items-start gap-6">
        <div class="rounded-lg border border-gray-200 p-3">
          {Phoenix.HTML.raw(GS1.qr_svg(@pass.gs1_identifier.digital_link, width: 200))}
        </div>
        <div class="text-sm text-gray-700">
          <p><span class="font-medium">GSRN:</span> <code>{@pass.gs1_identifier.value}</code></p>
          <p><span class="font-medium">Valid from:</span> {@pass.valid_from}</p>
          <p><span class="font-medium">Valid to:</span> {@pass.valid_to}</p>
          <p>
            <span class="font-medium">Interoperable:</span>
            <.badge kind={if @pass.gs1_identifier.interoperable, do: :success, else: :warning}>
              {if @pass.gs1_identifier.interoperable, do: "yes", else: "no — org has no GS1 prefix"}
            </.badge>
          </p>
        </div>
      </div>
    </.card>

    <p :if={!@pass} class="mt-6 text-sm text-gray-500">This visitor has no active pass.</p>

    <.card title={"Visit history · #{@visit_count} visit(s)"} class="mt-6">
      <.table id="visitor-history" rows={@history}>
        <:col :let={log} label="Direction">
          <.badge kind={(log.direction == "in" && :success) || :neutral}>{log.direction}</.badge>
        </:col>
        <:col :let={log} label="Access point">{log.access_point.name}</:col>
        <:col :let={log} label="When">{Calendar.strftime(log.scanned_at, "%d %b %Y, %H:%M")}</:col>
        <:empty>No scans recorded for this visitor yet.</:empty>
      </.table>
    </.card>
  </Layouts.app>
  """
end

  @impl true
def mount(%{"id" => id}, _session, socket) do
  scope = socket.assigns.current_scope
  visitor = Access.get_visitor_for_scope!(scope, id)
  pass = Access.get_active_pass_for_visitor(scope, visitor.id)
  history = Access.list_visitor_scan_history(scope, visitor)

  {:ok,
   socket
   |> assign(:visitor, visitor)
   |> assign(:pass, pass)
   |> assign(:history, history)
   |> assign(:visit_count, Enum.count(history, &(&1.direction == "in")))}
end
end
