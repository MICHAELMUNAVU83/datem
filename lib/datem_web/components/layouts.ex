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

  attr :max_width, :string,
    default: "max-w-6xl",
    doc: "content width, e.g. 'max-w-6xl' or 'max-w-full'"

  slot :inner_block, required: true

  def app(assigns) do
    assigns =
      assigns
      |> assign(:memberships, list_memberships(assigns.current_scope))
      |> assign(:has_access, Organizations.has_module?(assigns.current_scope, :access))
      |> assign(:has_ticketing, Organizations.has_module?(assigns.current_scope, :ticketing))

    ~H"""
    <div class="flex h-screen bg-gray-50">
      <aside class="flex w-64 shrink-0 flex-col border-r border-gray-200 bg-white">
        <div class="flex h-16 items-center gap-2 border-b border-gray-200 px-6">
          <span class="text-lg font-semibold tracking-tight text-blue-600">Datem</span>
        </div>

        <nav
          id="sidebar-nav"
          phx-hook=".NavActiveState"
          class="flex-1 space-y-6 overflow-y-auto px-3 py-6"
        >
          <input
            :if={@has_access and @has_ticketing}
            type="radio"
            name="module-tab"
            id="tab-access"
            class="peer/access sr-only"
          />
          <input
            :if={@has_access and @has_ticketing}
            type="radio"
            name="module-tab"
            id="tab-ticketing"
            class="peer/ticketing sr-only"
          />

          <div
            :if={@has_access and @has_ticketing}
            class="grid grid-cols-2 gap-1 rounded-lg bg-gray-100 p-1 text-sm font-medium"
          >
            <label
              for="tab-access"
              class="cursor-pointer rounded-md px-3 py-1.5 text-center text-gray-500 hover:text-gray-700 peer-checked/access:bg-white peer-checked/access:text-gray-900 peer-checked/access:shadow-sm"
            >
              Access
            </label>
            <label
              for="tab-ticketing"
              class="cursor-pointer rounded-md px-3 py-1.5 text-center text-gray-500 hover:text-gray-700 peer-checked/ticketing:bg-white peer-checked/ticketing:text-gray-900 peer-checked/ticketing:shadow-sm"
            >
              Events
            </label>
          </div>

          <div
            :if={@has_access}
            class={[@has_ticketing && "hidden peer-checked/access:block", "space-y-6"]}
          >
            <div>
              <p class="px-3 text-xs font-semibold uppercase tracking-wide text-gray-400">Overview</p>
              <ul class="mt-2 space-y-1">
                <li>
                  <.link
                    navigate={~p"/dashboard"}
                    data-nav-link
                    class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm text-gray-700 hover:bg-gray-100"
                  >
                    <.icon name="hero-home" class="size-4" /> Today
                  </.link>
                </li>
                <li :for={
                  {label, icon, path, roles} <- [
                    {"Access report", "hero-chart-bar", ~p"/reports/access",
                     [:owner, :admin, :viewer]},
                    {"Exports", "hero-arrow-down-tray", ~p"/exports", [:owner, :admin]}
                  ]
                }>

                  <%= if Organizations.has_role?(@current_scope, roles) do %>
                    <.link
                      navigate={path}
                      data-nav-link
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
              <p class="mt-6 px-3 text-xs font-semibold uppercase tracking-wide text-gray-400">
                Visitor Access
              </p>
              <ul class="mt-2 space-y-1">
                <li>
                  <.link
                    navigate={~p"/onsite"}
                    data-nav-link
                    class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm text-gray-700 hover:bg-gray-100"
                  >
                    <.icon name="hero-users" class="size-4" /> On-site now
                  </.link>
                </li>
                <li>
                  <.link
                    navigate={~p"/scan"}
                    data-nav-link
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
                    data-nav-link
                    class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm text-gray-700 hover:bg-gray-100"
                  >
                    <.icon name={icon} class="size-4" /> {label}
                  </.link>
                </li>
                <li :for={
                  {label, icon, path} <- [
                    {"Access points", "hero-map-pin", ~p"/access-points"},
                    {"Locations", "hero-building-office-2", ~p"/sites"}
                  ]
                }>
                  <%= if Organizations.has_role?(@current_scope, [:owner, :admin]) do %>
                    <.link
                      navigate={path}
                      data-nav-link
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
                <li>
                  <%= if Organizations.has_role?(@current_scope, [:owner, :admin]) do %>
                    <.link
                      navigate={~p"/organization/employees"}
                      data-nav-link
                      class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm text-gray-700 hover:bg-gray-100"
                    >
                      <.icon name="hero-user-group" class="size-4" /> Staff
                    </.link>
                  <% else %>
                    <span class="flex cursor-not-allowed items-center gap-2 rounded-lg px-3 py-2 text-sm text-gray-400">
                      <.icon name="hero-user-group" class="size-4" /> Staff
                    </span>
                  <% end %>
                </li>
                <li>
                  <.link
                    navigate={~p"/passes/employees"}
                    class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm text-gray-700 hover:bg-gray-100"
                  >
                    <.icon name="hero-arrow-right-start-on-rectangle" class="size-4" /> Exit passes
                  </.link>
                </li>
                <li>
                  <.link
                    navigate={~p"/passes/items"}
                    class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm text-gray-700 hover:bg-gray-100"
                  >
                    <.icon name="hero-archive-box" class="size-4" /> Item passes
                  </.link>
                </li>
                <li>
                  <.link
                    navigate={~p"/passes/cars"}
                    class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm text-gray-700 hover:bg-gray-100"
                  >
                    <.icon name="hero-truck" class="size-4" /> Car passes
                  </.link>
                </li>
                <li>
                  <.link
                    navigate={~p"/scan-history"}
                    class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm text-gray-700 hover:bg-gray-100"
                  >
                    <.icon name="hero-clock" class="size-4" /> Scan history
                  </.link>
                </li>
              </ul>
            </div>
          </div>

          <div :if={@has_ticketing} class={@has_access && "hidden peer-checked/ticketing:block"}>
            <p class="px-3 text-xs font-semibold uppercase tracking-wide text-gray-400">Events</p>
            <ul class="mt-2 space-y-1">
              <li :if={!@has_access}>
                <.link
                  navigate={~p"/dashboard"}
                  data-nav-link
                  class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm text-gray-700 hover:bg-gray-100"
                >
                  <.icon name="hero-home" class="size-4" /> Today
                </.link>
              </li>
              <li>
                <.link
                  navigate={~p"/events"}
                  data-nav-link
                  class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm text-gray-700 hover:bg-gray-100"
                >
                  <.icon name="hero-ticket" class="size-4" /> Events
                </.link>
              </li>
              <li>
                <.link
                  navigate={~p"/checkpoints"}
                  data-nav-link
                  class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm text-gray-700 hover:bg-gray-100"
                >
                  <.icon name="hero-viewfinder-circle" class="size-4" /> Checkpoints
                </.link>
              </li>
              <li>
                <%= if Organizations.has_role?(@current_scope, [:owner, :admin, :viewer]) do %>
                  <.link
                    navigate={~p"/reports/events"}
                    data-nav-link
                    class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm text-gray-700 hover:bg-gray-100"
                  >
                    <.icon name="hero-presentation-chart-line" class="size-4" /> Event report
                  </.link>
                <% else %>
                  <span class="flex cursor-not-allowed items-center gap-2 rounded-lg px-3 py-2 text-sm text-gray-400">
                    <.icon name="hero-presentation-chart-line" class="size-4" /> Event report
                  </span>
                <% end %>
              </li>
              <li>
                <%= if Organizations.has_role?(@current_scope, [:owner, :admin]) do %>
                  <.link
                    navigate={~p"/scan-types"}
                    data-nav-link
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
                    data-nav-link
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

              <li :if={@current_scope && @current_scope.user && @current_scope.user.platform_admin}>
                <.link
                  navigate={~p"/admin/organizations"}
                  data-nav-link
                  class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm text-gray-700 hover:bg-gray-100"
                >
                  <.icon name="hero-shield-check" class="size-4" /> Companies
                </.link>
              </li>
              <li>
                <%= if Organizations.has_role?(@current_scope, [:owner, :admin]) do %>
                  <.link
                    navigate={~p"/organization/settings"}
                    data-nav-link
                    class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm text-gray-700 hover:bg-gray-100"
                  >
                    <.icon name="hero-qr-code" class="size-4" /> Organization Settings
                  </.link>
                <% else %>
                  <span class="flex cursor-not-allowed items-center gap-2 rounded-lg px-3 py-2 text-sm text-gray-400">
                    <.icon name="hero-qr-code" class="size-4" /> Organization Settings
                  </span>
                <% end %>
              </li>
            </ul>
          </div>

          <script :type={Phoenix.LiveView.ColocatedHook} name=".NavActiveState">
            export default {
              mounted() { this.sync() },
              updated() { this.sync() },

              sync() {
                const path = window.location.pathname

                const ticketingPrefixes = ["/events", "/checkpoints", "/scan-types", "/reports/events"]
                const isTicketing = ticketingPrefixes.some(p => path.startsWith(p))
                const tabAccess = this.el.querySelector("#tab-access")
                const tabTicketing = this.el.querySelector("#tab-ticketing")
                if (tabAccess && tabTicketing) {
                  tabAccess.checked = !isTicketing
                  tabTicketing.checked = isTicketing
                }

                this.el.querySelectorAll("a[data-nav-link]").forEach(link => {
                  const href = link.getAttribute("href")
                  const active = href === path
                  link.classList.toggle("text-blue-600", active)
                  link.classList.toggle("bg-gray-50", active)
                  link.classList.toggle("font-medium", active)
                  link.classList.toggle("text-gray-700", !active)
                })
              }
            }
          </script>
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
          <div class={["mx-auto", @max_width]}>
            {render_slot(@inner_block)}
          </div>
        </main>
      </div>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Renders pagination controls: previous/next buttons plus page numbers.

  ## Examples

      <.pagination page={@page} total_pages={@total_pages} event="goto_page" />
  """
  attr :page, :integer, required: true
  attr :total_pages, :integer, required: true

  attr :event, :string,
    required: true,
    doc: "the phx-click event name to push with a 'page' value"

  def pagination(assigns) do
    ~H"""
    <div
      :if={@total_pages > 1}
      class="flex items-center justify-between border-t border-gray-200 bg-white px-6 py-3"
    >
      <p class="text-sm text-gray-500">
        Page {@page} of {@total_pages}
      </p>
      <div class="flex items-center gap-1">
        <button
          type="button"
          phx-click={@event}
          phx-value-page={@page - 1}
          disabled={@page <= 1}
          class="rounded-md px-2.5 py-1.5 text-sm font-medium text-gray-600 hover:bg-gray-100 disabled:cursor-not-allowed disabled:opacity-40"
        >
          <.icon name="hero-chevron-left" class="size-4" />
        </button>

        <button
          :for={p <- pagination_range(@page, @total_pages)}
          :if={p != :ellipsis}
          type="button"
          phx-click={@event}
          phx-value-page={p}
          class={[
            "min-w-8 rounded-md px-2.5 py-1.5 text-sm font-medium",
            (p == @page && "bg-blue-600 text-white") || "text-gray-600 hover:bg-gray-100"
          ]}
        >
          {p}
        </button>
        <span
          :for={p <- pagination_range(@page, @total_pages)}
          :if={p == :ellipsis}
          class="px-1 text-sm text-gray-400"
        >
          …
        </span>

        <button
          type="button"
          phx-click={@event}
          phx-value-page={@page + 1}
          disabled={@page >= @total_pages}
          class="rounded-md px-2.5 py-1.5 text-sm font-medium text-gray-600 hover:bg-gray-100 disabled:cursor-not-allowed disabled:opacity-40"
        >
          <.icon name="hero-chevron-right" class="size-4" />
        </button>
      </div>
    </div>
    """
  end

  defp pagination_range(_page, total) when total <= 7 do
    Enum.to_list(1..total)
  end

  defp pagination_range(page, total) do
    cond do
      page <= 4 ->
        [1, 2, 3, 4, 5, :ellipsis, total]

      page >= total - 3 ->
        [1, :ellipsis, total - 4, total - 3, total - 2, total - 1, total]

      true ->
        [1, :ellipsis, page - 1, page, page + 1, :ellipsis, total]
    end
  end

  @doc """
  Renders the split-screen layout used for login, registration, and other
  unauthenticated auth flows.

  Left half holds the form content passed in via the inner block; right half
  is a plain brand panel. Collapses to a single column on small screens.

  ## Examples

      <Layouts.auth flash={@flash}>
        <p>form content here</p>
      </Layouts.auth>
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  slot :inner_block, required: true

  def auth(assigns) do
    ~H"""
    <div class="flex min-h-screen">
      <div class="relative flex w-full flex-col justify-center px-6 py-12 sm:px-12 lg:w-1/2 lg:px-16">
        <!-- Subtle dot-grid pattern behind the form -->
        <div
          class="pointer-events-none absolute inset-0 opacity-40"
          style="background-image: radial-gradient(circle, #cbd5e1 1px, transparent 1px); background-size: 24px 24px;"
        >
        </div>

        <div class="relative mx-auto w-full max-w-sm">
          <.link navigate="/" class="mb-8 flex justify-center">
            <img src={~p"/images/datemlogo.png"} alt="Datem" class="h-28 w-auto" />
          </.link>

          <div class="rounded-2xl border border-gray-200 bg-white p-8 shadow-lg shadow-gray-200/50">
            {render_slot(@inner_block)}
          </div>
        </div>
      </div>

      <div class="relative hidden lg:flex lg:w-1/2 lg:items-center lg:justify-center overflow-hidden">
        <div
          class="absolute inset-0 bg-cover bg-center"
          style="background-image: url('https://images.unsplash.com/photo-1497366216548-37526070297c?auto=format&fit=crop&w=1600&q=80');"
        >
        </div>
        <!-- Even, darker overlay across the whole photo -->
        <div class="absolute inset-0 bg-black/60"></div>

        <div class="relative max-w-sm px-8 text-white">
          <p class="text-2xl font-semibold tracking-tight drop-shadow-lg">
            Access and ticketing, in one place.
          </p>
          <p class="mt-3 text-gray-200 drop-shadow-lg">
            Manage visitors, vehicles, and events across every site.
          </p>
        </div>
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
