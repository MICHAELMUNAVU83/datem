defmodule DatemWeb.AccessLive.ScanPicker do
  @moduledoc """
  Lets an operator choose which access point they're scanning at before
  entering the full-screen scanning view.
  """
  use DatemWeb, :live_view

  alias Datem.Access

  @impl true
 def render(assigns) do
  ~H"""
  <Layouts.app flash={@flash} current_scope={@current_scope} max_width="max-w-full">
    <div class="mb-6 overflow-hidden rounded-xl border border-blue-100">
      <.pass_header icon="hero-qr-code" title="Scan" subtitle="Choose the access point you're scanning at" />

      <div class="bg-white p-6">
        <ul :if={@access_points != []} class="grid gap-3 sm:grid-cols-2">
          <li :for={ap <- @access_points}>
            <.link
              navigate={~p"/scan/#{ap.id}"}
              class="flex flex-col gap-1 rounded-xl border border-gray-200 bg-white p-4 hover:border-blue-300 hover:bg-blue-50"
            >
              <span class="font-medium text-gray-900">{ap.name}</span>
              <span class="text-sm text-gray-500">{ap.site.name}</span>
            </.link>
          </li>
        </ul>

        <p :if={@access_points == []} class="text-sm text-gray-500">
          No access points yet. Ask an admin to add one before scanning.
        </p>
      </div>
    </div>
  </Layouts.app>
  """
end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :access_points, Access.list_access_points(socket.assigns.current_scope))}
  end
end
