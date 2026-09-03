defmodule DatemWeb.ScanningLive.ScanTypes do
  @moduledoc """
  Define the checkpoints ("Lunch", "Entry", "Session A", "Merch") an
  organisation scans at, and the rules the engine evaluates for each.

  A checkpoint belongs to exactly one event or one site; the scope is picked
  as a single `event:1` / `site:3` value so the two lists read as one choice.
  """
  use DatemWeb, :live_view

  on_mount {DatemWeb.UserAuth, {:require_role, [:owner, :admin]}}

  alias Datem.Access
  alias Datem.Scanning
  alias Datem.Scanning.ScanType
  alias Datem.Ticketing

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Scan types
        <:subtitle>Checkpoints operators can scan at, and the rules for each</:subtitle>
        <:actions>
          <.link navigate={~p"/checkpoints"}><.button>Start scanning</.button></.link>
        </:actions>
      </.header>

      <.table id="scan-types" rows={@scan_types}>
        <:col :let={st} label="Name">{st.name}</:col>
        <:col :let={st} label="Scope">{scope_label(st)}</:col>
        <:col :let={st} label="Window">{window_label(st)}</:col>
        <:col :let={st} label="Rules">
          <span class="flex flex-wrap gap-1">
            <.badge :for={rule <- rule_labels(st)} kind={:info}>{rule}</.badge>
          </span>
        </:col>
        <:col :let={st} label="Status">
          <.badge kind={if st.active, do: :success, else: :neutral}>
            {if st.active, do: "Active", else: "Off"}
          </.badge>
        </:col>
        <:action :let={st}>
          <.link phx-click="edit" phx-value-id={st.id}>Edit</.link>
        </:action>
        <:action :let={st}>
          <.link phx-click="toggle" phx-value-id={st.id}>
            {if st.active, do: "Switch off", else: "Switch on"}
          </.link>
        </:action>
        <:empty>No scan types yet. Define your first checkpoint below.</:empty>
      </.table>

      <div class="divider" />

      <.header>{if @editing, do: "Edit scan type", else: "Add a scan type"}</.header>

      <.form for={@form} id="scan_type_form" phx-submit="save" phx-change="validate">
        <div class="grid gap-4 sm:grid-cols-2">
          <.input field={@form[:name]} type="text" label="Name" required />
          <.input
            :if={!@editing}
            name="scan_type[scope]"
            id="scan_type_scope"
            value={@scope_value}
            type="select"
            label="Event or site"
            prompt="Choose where this checkpoint lives"
            options={@scope_options}
            required
          />
          <.input field={@form[:active_from]} type="datetime-local" label="Opens at (optional)" />
          <.input field={@form[:active_to]} type="datetime-local" label="Closes at (optional)" />
        </div>

        <.inputs_for :let={rules} field={@form[:rules]}>
          <div class="mt-4 rounded-xl border border-gray-200 bg-white p-4">
            <p class="mb-3 text-sm font-medium text-gray-900">Rules</p>

            <.input
              field={rules[:once_per_subject]}
              type="checkbox"
              label="Once per attendee (a second scan is a duplicate)"
            />
            <.input
              field={rules[:requires_check_in]}
              type="checkbox"
              label="Requires the attendee to be checked in to the event"
            />

            <div class="mt-3 grid gap-4 sm:grid-cols-2">
              <.input
                field={rules[:requires_prior_scan_type_id]}
                type="select"
                label="Requires a prior scan at"
                prompt="No prior scan required"
                options={@prior_scan_options}
              />
              <.input
                field={rules[:allowed_ticket_type_ids]}
                type="select"
                multiple
                label="Allowed ticket types (none selected = all)"
                options={@ticket_type_options}
              />
            </div>
          </div>
        </.inputs_for>

        <div class="mt-4 flex gap-3">
          <.button phx-disable-with="Saving...">Save</.button>
          <.button :if={@editing} type="button" phx-click="cancel_edit">Cancel</.button>
        </div>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:editing, false)
     |> assign(:scan_type, nil)
     |> assign(:scope_value, nil)
     |> assign_options()
     |> assign_scan_types()
     |> assign_form(Scanning.change_scan_type(%ScanType{}))}
  end

  @impl true
  def handle_event("validate", %{"scan_type" => params}, socket) do
    changeset =
      current_scan_type(socket)
      |> Scanning.change_scan_type(normalize(params, socket))
      |> Map.put(:action, :validate)

    {:noreply, socket |> assign(:scope_value, params["scope"]) |> assign_form(changeset)}
  end

  def handle_event("save", %{"scan_type" => params}, socket) do
    scope = socket.assigns.current_scope
    attrs = normalize(params, socket)

    result =
      if socket.assigns.editing do
        Scanning.update_scan_type(scope, socket.assigns.scan_type, attrs)
      else
        Scanning.create_scan_type(scope, attrs)
      end

    case result do
      {:ok, _scan_type} ->
        {:noreply,
         socket
         |> put_flash(:info, "Scan type saved.")
         |> reset_form()
         |> assign_options()
         |> assign_scan_types()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    scan_type = Scanning.get_scan_type_for_scope!(socket.assigns.current_scope, id)

    {:noreply,
     socket
     |> assign(:editing, true)
     |> assign(:scan_type, scan_type)
     |> assign(:scope_value, scope_value(scan_type))
     |> assign_form(Scanning.change_scan_type(scan_type))}
  end

  def handle_event("cancel_edit", _params, socket), do: {:noreply, reset_form(socket)}

  def handle_event("toggle", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    scan_type = Scanning.get_scan_type_for_scope!(scope, id)
    {:ok, _} = Scanning.set_active(scope, scan_type, !scan_type.active)

    {:noreply, assign_scan_types(socket)}
  end

  # The scope select carries "event:1"/"site:3"; the schema wants one of the
  # two foreign keys set and the other nil.
  defp normalize(params, socket) do
    params
    |> Map.delete("scope")
    |> Map.merge(scope_params(params["scope"], socket))
    |> Map.update("rules", %{}, &normalize_rules/1)
  end

  defp scope_params(nil, _socket), do: %{}
  defp scope_params("", _socket), do: %{}
  defp scope_params("event:" <> id, _socket), do: %{"event_id" => id, "site_id" => nil}
  defp scope_params("site:" <> id, _socket), do: %{"site_id" => id, "event_id" => nil}

  # An unchecked multi-select posts nothing at all, which would otherwise leave
  # a previously-saved restriction in place when editing.
  defp normalize_rules(rules) do
    Map.put_new(rules, "allowed_ticket_type_ids", [])
  end

  defp reset_form(socket) do
    socket
    |> assign(:editing, false)
    |> assign(:scan_type, nil)
    |> assign(:scope_value, nil)
    |> assign_form(Scanning.change_scan_type(%ScanType{}))
  end

  defp current_scan_type(socket), do: socket.assigns.scan_type || %ScanType{}

  defp assign_scan_types(socket) do
    scan_types = Scanning.list_scan_types(socket.assigns.current_scope)

    socket
    |> assign(:scan_types, scan_types)
    |> assign(:prior_scan_options, Enum.map(scan_types, &{&1.name, &1.id}))
  end

  defp assign_options(socket) do
    scope = socket.assigns.current_scope
    events = Ticketing.list_events(scope)
    sites = Access.list_sites(scope)

    ticket_type_options =
      for event <- events,
          ticket_type <- Ticketing.list_ticket_types(scope, event),
          do: {"#{event.name} · #{ticket_type.name}", ticket_type.id}

    socket
    |> assign(:scope_options, [
      {"Events", Enum.map(events, &{&1.name, "event:#{&1.id}"})},
      {"Sites", Enum.map(sites, &{&1.name, "site:#{&1.id}"})}
    ])
    |> assign(:ticket_type_options, ticket_type_options)
  end

  defp assign_form(socket, changeset),
    do: assign(socket, :form, to_form(changeset, as: "scan_type"))

  defp scope_value(%ScanType{event_id: nil, site_id: site_id}), do: "site:#{site_id}"
  defp scope_value(%ScanType{event_id: event_id}), do: "event:#{event_id}"

  defp scope_label(%ScanType{event: %{name: name}}), do: name
  defp scope_label(%ScanType{site: %{name: name}}), do: name
  defp scope_label(%ScanType{}), do: "—"

  defp window_label(%ScanType{active_from: nil, active_to: nil}), do: "Always"

  defp window_label(%ScanType{active_from: from, active_to: to}) do
    "#{format_time(from)} – #{format_time(to)}"
  end

  defp format_time(nil), do: "…"
  defp format_time(datetime), do: Calendar.strftime(datetime, "%d %b %H:%M")

  defp rule_labels(%ScanType{rules: nil}), do: []

  defp rule_labels(%ScanType{rules: rules}) do
    [
      rules.once_per_subject && "Once per attendee",
      rules.requires_check_in && "Must be checked in",
      rules.requires_prior_scan_type_id && "Requires a prior scan",
      rules.allowed_ticket_type_ids != [] && "Ticket-type restricted"
    ]
    |> Enum.filter(&is_binary/1)
  end
end
