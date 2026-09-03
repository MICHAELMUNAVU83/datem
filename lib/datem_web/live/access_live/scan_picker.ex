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
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Scan
        <:subtitle>Choose the access point you're scanning at</:subtitle>
      </.header>

      <ul :if={@access_points != []} class="mt-4 grid gap-3 sm:grid-cols-2">
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

      <p :if={@access_points == []} class="mt-4 text-sm text-gray-500">
        No access points yet. Ask an admin to add one before scanning.
      </p>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :access_points, Access.list_access_points(socket.assigns.current_scope))}
  end
end
