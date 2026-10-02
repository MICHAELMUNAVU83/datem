defmodule DatemWeb.TicketingLive.Attendees do
  @moduledoc """
  Attendees for a single event: register walk-ins, view registration
  status, resend a ticket email, and watch a live checked-in count as
  scans come in at the door.
  """

  use DatemWeb, :live_view

  on_mount {DatemWeb.UserAuth, {:require_role, [:owner, :admin, :operator]}}

  alias Datem.Ticketing
  alias Datem.Ticketing.Ticket
  alias Datem.Tenancy
  alias Datem.GS1


  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope
    event = Ticketing.get_event_for_scope!(scope, id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(
        Datem.PubSub,
        Ticketing.event_topic(Tenancy.organization_id!(scope), event.id)
      )
    end

    {:ok,
     socket
     |> assign(:event, event)
     |> assign(:show_form, false)
     |> assign(:tickets, Ticketing.list_tickets(scope, event))
     |> assign(:stats, Ticketing.event_stats(scope, event))
     |> assign(:editing_ticket, nil)
     |> assign(:show_import_form, false)
     |> assign(:qr_ticket, nil)
     |> assign(:qr_link, nil)
     |> assign(:import_ticket_type_id, nil)
     |> allow_upload(:csv, accept: ~w(.csv), max_entries: 1, max_file_size: 2_000_000)
     |> assign_form()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} max_width="max-w-full">
      <div class="mb-6 overflow-hidden rounded-xl border border-blue-100">
        <.pass_header icon="hero-ticket" title={"#{@event.name} · Attendees"} subtitle={@event.venue}>
          <.link navigate={~p"/events/#{@event.id}"}>
            <.button variant="secondary">Back to event</.button>
          </.link>
          <.button phx-click="new">Register an attendee</.button>
          <.button phx-click="new_import">Import attendees</.button>
        </.pass_header>

        <div class="grid gap-4 border-b border-gray-200 bg-white p-6 sm:grid-cols-2">
          <.stat_card label="Registered" value={@stats.registered} />
          <.stat_card label="Checked in now" value={@stats.checked_in} icon="hero-users" />
        </div>

        <.table id="attendees" rows={@tickets}>
          <:col :let={t} label="Name">{t.attendee_name}</:col>
          <:col :let={t} label="Email">{t.attendee_email || "—"}</:col>
          <:col :let={t} :if={"company" in @event.required_attendee_fields} label="Company">
            {t.company}
          </:col>
          <:col :let={t} :if={"id_number" in @event.required_attendee_fields} label="ID number">
            {t.id_number}
          </:col>
          <:col :let={t} :if={"phone_number" in @event.required_attendee_fields} label="Phone">
            {t.phone_number}
          </:col>
          <:col :let={t} :if={"gender" in @event.required_attendee_fields} label="Gender">
            {t.gender}
          </:col>
          <:col :let={t} :if={"dob" in @event.required_attendee_fields} label="DOB">
            {t.dob}
          </:col>
          <:col :let={t} label="Ticket type">{t.ticket_type.name}</:col>
          <:col :let={t} label="Status">
            <.badge kind={ticket_status_kind(t.status)}>{t.status}</.badge>
          </:col>
          <:action :let={t}>
            <.link phx-click="edit" phx-value-id={t.id}>Edit</.link>
          </:action>
          <:action :let={t}>
            <.link :if={t.gs1_identifier} phx-click="view_qr" phx-value-id={t.id}>View QR</.link>
          </:action>
          <:action :let={t}>
            <.link :if={t.attendee_email} phx-click="resend" phx-value-id={t.id}>Resend QR</.link>
          </:action>
          <:empty>No attendees yet. Register one with the button above.</:empty>
        </.table>
      </div>

      <.modal :if={@show_import_form} id="import-modal" show on_cancel={JS.push("close_import_form")}>
        <.header>Import attendees</.header>
        <p class="mb-4 text-sm text-gray-600">
          CSV with a <code>name</code>
          column (required) and optional <code>email</code>, <code>company</code>, <code>id_number</code>, <code>phone_number</code>, <code>gender</code>,
          <code>dob</code>
          columns.
        </p>

        <form phx-submit="import" phx-change="noop">
          <div class="flex flex-col gap-2">
            <label class="text-sm font-medium text-gray-700">Ticket type</label>
            <select name="ticket_type_id" class="w-full rounded-lg border-gray-300 text-sm">
              <option :for={t <- @event.ticket_types} value={t.id}>{t.name}</option>
            </select>
          </div>

          <div class="mt-4">
            <.live_file_input upload={@uploads.csv} class="text-sm" />
            <p :for={err <- upload_errors(@uploads.csv)} class="mt-1.5 text-sm text-red-600">
              {err}
            </p>
          </div>

          <div class="mt-4 flex gap-3">
            <.button phx-disable-with="Importing...">Import</.button>
            <.button type="button" variant="secondary" phx-click="close_import_form">Cancel</.button>
          </div>
        </form>
      </.modal>

      <.modal :if={@qr_ticket} id="qr-modal" show on_cancel={JS.push("close_qr")}>
        <.header>{@qr_ticket.attendee_name}'s ticket</.header>

        <div class="flex flex-col items-center gap-4">
          <div class="rounded-xl border border-gray-200 p-4">
            {Phoenix.HTML.raw(GS1.qr_svg(@qr_ticket.gs1_identifier.digital_link, width: 220))}
          </div>

          <div class="w-full">
            <label class="mb-1.5 block text-sm font-medium text-gray-700">Public ticket link</label>
            <div class="flex gap-2">
              <input
                type="text"
                readonly
                value={@qr_link}
                class="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm text-gray-600 shadow-sm"
                onclick="this.select()"
              />
              <.link href={@qr_link} target="_blank" rel="noopener noreferrer">
                <.button variant="secondary">Open</.button>
              </.link>
            </div>
          </div>
        </div>

        <div class="mt-4 flex gap-3">
          <.button type="button" variant="secondary" phx-click="close_qr">Close</.button>
        </div>
      </.modal>

      <.modal :if={@show_form} id="attendee-modal" show on_cancel={JS.push("close_form")}>
        <.header>Register an attendee</.header>

        <.form for={@form} id="attendee_form" phx-submit="save" phx-change="validate">
          <.input
            field={@form[:ticket_type_id]}
            type="select"
            label="Ticket type"
            options={Enum.map(@event.ticket_types, &{&1.name, &1.id})}
            required
          />
          <.input field={@form[:attendee_name]} type="text" label="Full name" required />
          <.input field={@form[:attendee_email]} type="email" label="Email" />
          <.input
            :if={"company" in @event.required_attendee_fields}
            field={@form[:company]}
            type="text"
            label="Company"
            required
          />
          <.input
            :if={"id_number" in @event.required_attendee_fields}
            field={@form[:id_number]}
            type="text"
            label="ID / passport number"
            required
          />
          <.input
            :if={"phone_number" in @event.required_attendee_fields}
            field={@form[:phone_number]}
            type="text"
            label="Phone number"
            required
          />
          <.input
            :if={"gender" in @event.required_attendee_fields}
            field={@form[:gender]}
            type="select"
            label="Gender"
            options={[{"Male", "male"}, {"Female", "female"}, {"Prefer not to say", "other"}]}
            prompt="Select"
            required
          />
          <.input
            :if={"dob" in @event.required_attendee_fields}
            field={@form[:dob]}
            type="date"
            label="Date of birth"
            required
          />

          <div class="mt-4 flex gap-3">
            <.button phx-disable-with="Registering...">Register & send QR</.button>
            <.button type="button" variant="secondary" phx-click="close_form">Cancel</.button>
          </div>
        </.form>
      </.modal>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("new", _params, socket) do
    {:noreply, socket |> assign(:show_form, true) |> assign_form()}
  end

  def handle_event("close_form", _params, socket) do
    {:noreply, assign(socket, :show_form, false)}
  end

  def handle_event("validate", %{"ticket" => params}, socket) do
    changeset =
      %Ticket{}
      |> Ticket.changeset(params, socket.assigns.event.required_attendee_fields)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: "ticket"))}
  end

  def handle_event("edit", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    ticket = Ticketing.get_ticket_for_scope!(scope, id)

    {:noreply,
     socket
     |> assign(:editing_ticket, ticket)
     |> assign(:show_form, true)
     |> assign(
       :form,
       to_form(Ticket.changeset(ticket, %{}, socket.assigns.event.required_attendee_fields),
         as: "ticket"
       )
     )}
  end

  def handle_event("save", %{"ticket" => params}, socket) do
    event = socket.assigns.event
    scope = socket.assigns.current_scope

    result =
      case socket.assigns.editing_ticket do
        nil ->
          ticket_type =
            Enum.find(event.ticket_types, &(&1.id == String.to_integer(params["ticket_type_id"])))

          ticket_type && Ticketing.register_attendee(event, ticket_type, params)

        ticket ->
          Ticketing.update_ticket(scope, ticket, params)
      end

    case result do
      {:ok, _ticket} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           (socket.assigns.editing_ticket && "Attendee updated.") ||
             "Attendee registered — ticket emailed."
         )
         |> assign(:show_form, false)
         |> assign(:editing_ticket, nil)
         |> assign(:tickets, Ticketing.list_tickets(scope, event))
         |> assign(:stats, Ticketing.event_stats(scope, event))}

      {:error, :sold_out} ->
        {:noreply, put_flash(socket, :error, "That ticket type is sold out.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: "ticket"))}

      nil ->
        {:noreply, put_flash(socket, :error, "Please choose a ticket type.")}
    end
  end

  def handle_event("resend", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    ticket = Ticketing.get_ticket_for_scope!(scope, id)

    case Ticketing.resend_ticket_email(scope, ticket) do
      {:ok, _job} ->
        {:noreply, put_flash(socket, :info, "Ticket resent to #{ticket.attendee_email}.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Couldn't resend that ticket.")}
    end
  end

  def handle_event("view_qr", %{"id" => id}, socket) do
  scope = socket.assigns.current_scope
  ticket = Ticketing.get_ticket_for_scope!(scope, id)

  {:noreply,
   socket
   |> assign(:qr_ticket, ticket)
   |> assign(:qr_link, url(~p"/ticket/#{ticket.gs1_identifier.value}"))}
end

def handle_event("close_qr", _params, socket) do
  {:noreply, socket |> assign(:qr_ticket, nil) |> assign(:qr_link, nil)}
end

  def handle_event("new_import", _params, socket),
    do: {:noreply, assign(socket, :show_import_form, true)}

  def handle_event("close_import_form", _params, socket),
    do: {:noreply, assign(socket, :show_import_form, false)}

  def handle_event("noop", _params, socket), do: {:noreply, socket}

  def handle_event("import", %{"ticket_type_id" => ticket_type_id}, socket) do
    event = socket.assigns.event
    scope = socket.assigns.current_scope
    ticket_type = Enum.find(event.ticket_types, &(&1.id == String.to_integer(ticket_type_id)))

    [csv_binary] =
      consume_uploaded_entries(socket, :csv, fn %{path: path}, _entry ->
        {:ok, File.read!(path)}
      end)

    {ok_count, errors} = Ticketing.import_attendees(event, ticket_type, csv_binary)

    message =
      case errors do
        [] ->
          "Imported #{ok_count} attendee(s)."

        _ ->
          "Imported #{ok_count}, #{length(errors)} row(s) failed: " <>
            Enum.map_join(errors, "; ", fn {line, reason} -> "line #{line} (#{reason})" end)
      end

    {:noreply,
     socket
     |> put_flash((errors == [] && :info) || :error, message)
     |> assign(:show_import_form, false)
     |> assign(:tickets, Ticketing.list_tickets(scope, event))
     |> assign(:stats, Ticketing.event_stats(scope, event))}
  end

  @impl true
  def handle_info({:ticket_scanned, _log}, socket) do
    scope = socket.assigns.current_scope
    event = socket.assigns.event

    {:noreply,
     socket
     |> assign(:tickets, Ticketing.list_tickets(scope, event))
     |> assign(:stats, Ticketing.event_stats(scope, event))}
  end



  defp assign_form(socket) do
    assign(socket, :form, to_form(Ticket.changeset(%Ticket{}, %{}), as: "ticket"))
  end

  defp ticket_status_kind("checked_in"), do: :success
  defp ticket_status_kind("cancelled"), do: :danger
  defp ticket_status_kind(_), do: :info
end
