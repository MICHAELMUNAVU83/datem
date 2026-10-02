defmodule DatemWeb.ScanningLive.ScanPicker do
  @moduledoc """
  Lets an operator pick which checkpoint they're scanning at — only the ones
  that are switched on and inside their active window are offered.
  """
  use DatemWeb, :live_view

  alias Datem.Scanning

  @impl true
def render(assigns) do
  ~H"""
  <Layouts.app flash={@flash} current_scope={@current_scope} max_width="max-w-full">
    <div class="mb-6 overflow-hidden rounded-xl border border-blue-100">
      <.pass_header icon="hero-viewfinder-circle" title="Checkpoints" subtitle="Choose the scan type you're scanning for" />

      <div class="bg-white p-6">
        <ul :if={@scan_types != []} class="grid gap-3 sm:grid-cols-2">
          <li :for={scan_type <- @scan_types}>
            <.link
              navigate={~p"/checkpoints/#{scan_type.id}"}
              class="flex flex-col gap-1 rounded-xl border border-gray-200 bg-white p-4 hover:border-blue-300 hover:bg-blue-50"
            >
              <span class="font-medium text-gray-900">{scan_type.name}</span>
              <span class="text-sm text-gray-500">{scope_label(scan_type)}</span>
            </.link>
          </li>
        </ul>

        <p :if={@scan_types == []} class="text-sm text-gray-500">
          No checkpoints are open right now. Ask an admin to add or switch one on.
        </p>
      </div>
    </div>
  </Layouts.app>
  """
end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket, :scan_types, Scanning.list_scannable_scan_types(socket.assigns.current_scope))}
  end

  defp scope_label(%{event: %{name: name}}), do: name
  defp scope_label(%{site: %{name: name}}), do: name
  defp scope_label(_), do: nil
end
