defmodule DatemWeb.TicketingLive.EventShow do
  @moduledoc """
  Manage an event's ticket types and public join link, and watch its live
  dashboard: registered vs checked-in counts, per-ticket-type tallies, and
  a live scan feed.
  """
  use DatemWeb, :live_view

  on_mount {DatemWeb.UserAuth, {:require_role, [:owner, :admin, :operator]}}

  alias Datem.Scanning
  alias Datem.Ticketing
  alias Datem.Ticketing.TicketType
  alias Datem.Tenancy

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope
    event = Ticketing.get_event_for_scope!(scope, id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(
        Datem.PubSub,
        Ticketing.event_topic(Tenancy.organization_id!(scope), event.id)
      )

      Scanning.subscribe(scope)
    end

    {:ok,
     socket
     |> assign(:event, event)
     |> assign(:show_form, false)
     |> assign(:join_url, event.join_link_token && url(~p"/join/#{event.join_link_token}"))
     |> assign_ticket_types()
     |> assign_stats()
     |> assign_tallies()
     |> assign(:recent_scans, Ticketing.list_recent_scans(scope, event))
     |> assign_form(Ticketing.change_ticket_type(%TicketType{}))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@event.name}
        <:subtitle>{@event.venue}</:subtitle>
        <:actions>
          <.link navigate={~p"/events/#{@event.id}/scan"}>
            <.button>Check-in scanning</.button>
          </.link>
          <.button phx-click="new_join_link">Create join link</.button>
        </:actions>
      </.header>

      <div :if={@join_url} class="mb-4 rounded-lg border border-blue-200 bg-blue-50 p-4 text-sm">
        <p class="font-medium text-blue-900">Share this link so attendees can register:</p>
        <code class="mt-1 block break-all text-blue-800">{@join_url}</code>
      </div>

      <div class="grid gap-4 sm:grid-cols-2">
        <.stat_card label="Registered" value={@stats.registered} />
        <.stat_card label="Checked in" value={@stats.checked_in} />
      </div>

      <div class="divider" />

      <.header>
        Scan types
        <:subtitle>Live tallies for this event's checkpoints</:subtitle>
        <:actions>
          <.link navigate={~p"/scan-types"}><.button>Configure</.button></.link>
        </:actions>
      </.header>

      <div :if={@tallies != []} class="grid gap-4 sm:grid-cols-3">
        <.stat_card
          :for={tally <- @tallies}
          label={tally.scan_type.name}
          value={tally_value(tally)}
          hint={tally_hint(tally)}
        />
      </div>

      <p :if={@tallies == []} class="text-sm text-gray-500">
        No scan types for this event yet — add "Lunch", "Session A" or similar to track them here.
      </p>

      <div class="divider" />

      <.header>
        Ticket types
        <:actions>
          <.button phx-click="new">Add ticket type</.button>
        </:actions>
      </.header>

      <.table id="ticket-types" rows={@ticket_types}>
        <:col :let={t} label="Name">{t.name}</:col>
        <:col :let={t} label="Price">{t.price}</:col>
        <:col :let={t} label="Quantity">{t.quantity || "Unlimited"}</:col>
        <:col :let={t} label="Per-attendee limit">{t.per_attendee_limit}</:col>
        <:empty>No ticket types yet. Add one with the button above.</:empty>
      </.table>

      <.modal :if={@show_form} id="ticket-type-modal" show on_cancel={JS.push("close_form")}>
        <.header>Add a ticket type</.header>

        <.form for={@form} id="ticket_type_form" phx-submit="save" phx-change="validate">
          <.input field={@form[:name]} type="text" label="Name" required />
          <.input field={@form[:price]} type="number" label="Price" step="0.01" />
          <.input field={@form[:quantity]} type="number" label="Quantity (blank = unlimited)" />
          <.input field={@form[:per_attendee_limit]} type="number" label="Per-attendee limit" />

          <div class="mt-4 flex gap-3">
            <.button phx-disable-with="Adding...">Add ticket type</.button>
            <.button type="button" variant="secondary" phx-click="close_form">Cancel</.button>
          </div>
        </.form>
      </.modal>

      <div class="divider" />

      <.header>Live scan feed</.header>

      <.table id="recent-scans" rows={@recent_scans}>
        <:col :let={s} label="Attendee">{s.ticket.attendee_name}</:col>
        <:col :let={s} label="Direction">{s.direction}</:col>
        <:col :let={s} label="Time">{Calendar.strftime(s.scanned_at, "%H:%M:%S")}</:col>
        <:empty>No scans yet.</:empty>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("validate", %{"ticket_type" => params}, socket) do
    changeset =
      %TicketType{} |> Ticketing.change_ticket_type(params) |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"ticket_type" => params}, socket) do
    case Ticketing.create_ticket_type(socket.assigns.current_scope, socket.assigns.event, params) do
      {:ok, _ticket_type} ->
        {:noreply,
         socket
         |> put_flash(:info, "Ticket type added.")
         |> assign(:show_form, false)
         |> assign_ticket_types()
         |> assign_form(Ticketing.change_ticket_type(%TicketType{}))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("new", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_form, true)
     |> assign_form(Ticketing.change_ticket_type(%TicketType{}))}
  end

  def handle_event("close_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_form, false)
     |> assign_form(Ticketing.change_ticket_type(%TicketType{}))}
  end

  def handle_event("new_join_link", _params, socket) do
    scope = socket.assigns.current_scope

    case Ticketing.create_join_link(scope, socket.assigns.event) do
      {:ok, event} ->
        {:noreply,
         assign(socket, event: event, join_url: url(~p"/join/#{event.join_link_token}"))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Couldn't create a join link.")}
    end
  end

  @impl true
  def handle_info({:ticket_scanned, _log}, socket) do
    scope = socket.assigns.current_scope

    {:noreply,
     socket
     |> assign_stats()
     |> assign(:recent_scans, Ticketing.list_recent_scans(scope, socket.assigns.event))}
  end

  def handle_info({:scan_logged, log}, socket) do
    # Only the checkpoints belonging to this event affect this dashboard.
    if log.scan_type_id in Enum.map(socket.assigns.tallies, & &1.scan_type.id) do
      {:noreply, assign_tallies(socket)}
    else
      {:noreply, socket}
    end
  end

  defp assign_tallies(socket) do
    scope = socket.assigns.current_scope
    scan_types = Scanning.list_scan_types_for(scope, socket.assigns.event)

    assign(socket, :tallies, Scanning.tallies(scope, scan_types))
  end

  defp tally_value(%{claimed: claimed, eligible: nil}), do: claimed
  defp tally_value(%{claimed: claimed, eligible: eligible}), do: "#{claimed}/#{eligible}"

  defp tally_hint(%{scan_type: %{active: false}}), do: "Switched off"
  defp tally_hint(_tally), do: "claimed"

  defp assign_ticket_types(socket) do
    assign(
      socket,
      :ticket_types,
      Ticketing.list_ticket_types(socket.assigns.current_scope, socket.assigns.event)
    )
  end

  defp assign_stats(socket) do
    assign(
      socket,
      :stats,
      Ticketing.event_stats(socket.assigns.current_scope, socket.assigns.event)
    )
  end

  defp assign_form(socket, changeset),
    do: assign(socket, :form, to_form(changeset, as: "ticket_type"))
end
