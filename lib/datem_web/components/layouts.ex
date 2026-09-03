defmodule DatemWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use DatemWeb, :html

  alias Datem.Organizations

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    assigns = assign(assigns, :memberships, list_memberships(assigns.current_scope))

    ~H"""
    <div class="flex h-screen bg-gray-50">
      <aside class="flex w-64 shrink-0 flex-col border-r border-gray-200 bg-white">
        <div class="flex h-16 items-center gap-2 border-b border-gray-200 px-6">
          <span class="text-lg font-semibold tracking-tight text-blue-600">Datem</span>
        </div>

        <nav class="flex-1 space-y-6 overflow-y-auto px-3 py-6">
          <div class="grid grid-cols-2 gap-1 rounded-lg bg-gray-100 p-1 text-sm font-medium">
            <button class="rounded-md bg-white px-3 py-1.5 text-gray-900 shadow-sm">Access</button>
            <button class="rounded-md px-3 py-1.5 text-gray-500 hover:text-gray-700">
              Ticketing
            </button>
          </div>

          <div>
            <p class="px-3 text-xs font-semibold uppercase tracking-wide text-gray-400">
              Overview
            </p>
            <ul class="mt-2 space-y-1">
              <li>
                <.link
                  navigate={~p"/dashboard"}
                  class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm text-gray-700 hover:bg-gray-100"
                >
                  <.icon name="hero-home" class="size-4" /> Today
                </.link>
              </li>
              <li :for={
                {label, icon, path, roles} <- [
                  {"Access report", "hero-chart-bar", ~p"/reports/access", [:owner, :admin, :viewer]},
                  {"Event report", "hero-presentation-chart-line", ~p"/reports/events",
                   [:owner, :admin, :viewer]},
                  {"Exports", "hero-arrow-down-tray", ~p"/exports", [:owner, :admin]}
                ]
              }>
                <%= if Organizations.has_role?(@current_scope, roles) do %>
                  <.link
                    navigate={path}
                    class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm text-gray-700 hover:bg-gray-100"
                  >
                    <.icon name={icon} class="size-4" /> {label}
                  </.link>
                <% else %>
                  <span class="flex cursor-not-allowed items-center gap-2 rounded-lg px-3 py-2 text-sm text-gray-400">
                    <.icon name={icon} class="size-4" /> {label}
                  </span>
                <% end %>
              </li>
            </ul>
          </div>

          <div>
            <p class="px-3 text-xs font-semibold uppercase tracking-wide text-gray-400">
              Visitor Access
            </p>
            <ul class="mt-2 space-y-1">
              <li>
                <.link
                  navigate={~p"/onsite"}
                  class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm text-gray-700 hover:bg-gray-100"
                >
                  <.icon name="hero-users" class="size-4" /> On-site now
                </.link>
              </li>
              <li>
                <.link
                  navigate={~p"/scan"}
                  class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm text-gray-700 hover:bg-gray-100"
                >
                  <.icon name="hero-qr-code" class="size-4" /> Scan
                </.link>
              </li>
              <li :for={
                {label, icon, path} <- [
                  {"Visitors", "hero-identification", ~p"/visitors"},
                  {"Vehicles", "hero-truck", ~p"/vehicles"}
                ]
              }>
                <.link
                  navigate={path}
                  class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm text-gray-700 hover:bg-gray-100"
                >
                  <.icon name={icon} class="size-4" /> {label}
                </.link>
              </li>
              <li :for={
                {label, icon, path} <- [
                  {"Access points", "hero-map-pin", ~p"/access-points"},
                  {"Sites", "hero-building-office-2", ~p"/sites"}
                ]
              }>
                <%= if Organizations.has_role?(@current_scope, [:owner, :admin]) do %>
                  <.link
                    navigate={path}
                    class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm text-gray-700 hover:bg-gray-100"
                  >
                    <.icon name={icon} class="size-4" /> {label}
                  </.link>
                <% else %>
                  <span class="flex cursor-not-allowed items-center gap-2 rounded-lg px-3 py-2 text-sm text-gray-400">
                    <.icon name={icon} class="size-4" /> {label}
                  </span>
                <% end %>
              </li>
            </ul>
          </div>

          <div>
            <p class="px-3 text-xs font-semibold uppercase tracking-wide text-gray-400">
              Ticketing
            </p>
            <ul class="mt-2 space-y-1">
              <li>
                <.link
                  navigate={~p"/events"}
                  class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm text-gray-700 hover:bg-gray-100"
                >
                  <.icon name="hero-ticket" class="size-4" /> Events
                </.link>
              </li>
              <li>
                <.link
                  navigate={~p"/checkpoints"}
                  class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm text-gray-700 hover:bg-gray-100"
                >
                  <.icon name="hero-viewfinder-circle" class="size-4" /> Checkpoints
                </.link>
              </li>
              <li>
                <%= if Organizations.has_role?(@current_scope, [:owner, :admin]) do %>
                  <.link
                    navigate={~p"/scan-types"}
                    class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm text-gray-700 hover:bg-gray-100"
                  >
                    <.icon name="hero-adjustments-horizontal" class="size-4" /> Scan types
                  </.link>
                <% else %>
                  <span class="flex cursor-not-allowed items-center gap-2 rounded-lg px-3 py-2 text-sm text-gray-400">
                    <.icon name="hero-adjustments-horizontal" class="size-4" /> Scan types
                  </span>
                <% end %>
              </li>
            </ul>
          </div>

          <div>
            <p class="px-3 text-xs font-semibold uppercase tracking-wide text-gray-400">Settings</p>
            <ul class="mt-2 space-y-1">
              <li>
                <%= if Organizations.has_role?(@current_scope, [:owner, :admin]) do %>
                  <.link
                    navigate={~p"/organization/members"}
                    class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm text-gray-700 hover:bg-gray-100"
                  >
                    <.icon name="hero-cog-6-tooth" class="size-4" /> Organisation
                  </.link>
                <% else %>
                  <span class="flex cursor-not-allowed items-center gap-2 rounded-lg px-3 py-2 text-sm text-gray-400">
                    <.icon name="hero-cog-6-tooth" class="size-4" /> Organisation
                  </span>
                <% end %>
              </li>
              <li>
                <%= if Organizations.has_role?(@current_scope, [:owner, :admin]) do %>
                  <.link
                    navigate={~p"/organization/settings"}
                    class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm text-gray-700 hover:bg-gray-100"
                  >
                    <.icon name="hero-qr-code" class="size-4" /> GS1 & identity
                  </.link>
                <% else %>
                  <span class="flex cursor-not-allowed items-center gap-2 rounded-lg px-3 py-2 text-sm text-gray-400">
                    <.icon name="hero-qr-code" class="size-4" /> GS1 & identity
                  </span>
                <% end %>
              </li>
            </ul>
          </div>
        </nav>
      </aside>

      <div class="flex min-w-0 flex-1 flex-col">
        <header class="flex h-16 shrink-0 items-center justify-between border-b border-gray-200 bg-white px-6">
          <details :if={@current_scope && @current_scope.user} class="group relative">
            <summary class="flex cursor-pointer list-none items-center gap-2 rounded-lg px-2 py-1.5 text-sm font-medium text-gray-700 marker:content-none hover:bg-gray-50">
              <span class="flex size-6 items-center justify-center rounded bg-blue-600 text-xs font-semibold text-white">
                {org_initial(@current_scope)}
              </span>
              {org_label(@current_scope)}
              <.icon name="hero-chevron-up-down" class="size-4 text-gray-400" />
            </summary>
            <div class="absolute left-0 z-10 mt-2 w-56 rounded-lg border border-gray-200 bg-white py-1 shadow-lg">
              <.link
                :for={membership <- @memberships}
                href={~p"/organizations/switch/#{membership.organization_id}"}
                class={[
                  "block px-4 py-2 text-sm hover:bg-gray-50",
                  (current_organization?(@current_scope, membership) && "font-semibold text-blue-600") ||
                    "text-gray-700"
                ]}
              >
                {membership.organization.name}
              </.link>
            </div>
          </details>
          <span :if={!@current_scope || !@current_scope.user} />

          <details class="group relative">
            <summary class="flex cursor-pointer list-none items-center gap-2 rounded-lg px-2 py-1.5 text-sm text-gray-700 marker:content-none hover:bg-gray-50">
              <span class="flex size-8 items-center justify-center rounded-full bg-gray-200 text-sm font-medium text-gray-600">
                {user_initial(@current_scope)}
              </span>
              <span class="max-w-40 truncate">{user_label(@current_scope)}</span>
              <.icon name="hero-chevron-down" class="size-4 text-gray-400" />
            </summary>
            <div class="absolute right-0 z-10 mt-2 w-48 rounded-lg border border-gray-200 bg-white py-1 shadow-lg">
              <%= if @current_scope do %>
                <.link
                  navigate={~p"/users/settings"}
                  class="block px-4 py-2 text-sm text-gray-700 hover:bg-gray-50"
                >
                  Settings
                </.link>
                <.link
                  href={~p"/users/log-out"}
                  method="delete"
                  class="block px-4 py-2 text-sm text-gray-700 hover:bg-gray-50"
                >
                  Log out
                </.link>
              <% else %>
                <.link
                  navigate={~p"/users/log-in"}
                  class="block px-4 py-2 text-sm text-gray-700 hover:bg-gray-50"
                >
                  Log in
                </.link>
                <.link
                  navigate={~p"/users/register"}
                  class="block px-4 py-2 text-sm text-gray-700 hover:bg-gray-50"
                >
                  Register
                </.link>
              <% end %>
            </div>
          </details>
        </header>

        <main class="flex-1 overflow-y-auto p-6 sm:p-8">
          <div class="mx-auto max-w-6xl">
            {render_slot(@inner_block)}
          </div>
        </main>
      </div>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Renders the full-screen scanning layout used at access points and event doors.

  Minimal chrome, optimised for a phone/tablet held at a gate.

  ## Examples

      <Layouts.scanning flash={@flash} title="Main Gate">
        <.scan_result result={:idle} title="Ready to scan" />
      </Layouts.scanning>
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :title, :string, required: true, doc: "the checkpoint/access point name"
  slot :inner_block, required: true

  def scanning(assigns) do
    ~H"""
    <div class="flex h-screen flex-col bg-gray-50">
      <header class="flex h-14 shrink-0 items-center justify-between border-b border-gray-200 bg-white px-4">
        <.link navigate="/" class="text-gray-400 hover:text-gray-600">
          <.icon name="hero-arrow-left" class="size-5" />
        </.link>
        <p class="text-sm font-medium text-gray-900">{@title}</p>
        <span class="size-5" />
      </header>

      <main class="flex flex-1 flex-col items-center justify-center gap-8 p-6">
        {render_slot(@inner_block)}
      </main>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  defp user_label(%{user: %{email: email}}), do: email
  defp user_label(_), do: "Guest"

  defp user_initial(scope), do: scope |> user_label() |> String.first() |> String.upcase()

  defp list_memberships(%{user: %Datem.Accounts.User{}} = scope) do
    Organizations.list_memberships_for_user(scope.user)
  end

  defp list_memberships(_scope), do: []

  defp org_label(%{organization: %{name: name}}), do: name
  defp org_label(_), do: "No organisation"

  defp org_initial(scope), do: scope |> org_label() |> String.first() |> String.upcase()

  defp current_organization?(%{organization: %{id: id}}, %{organization_id: id}), do: true
  defp current_organization?(_scope, _membership), do: false
end
