defmodule DatemWeb.TicketingLive.EventSchedule do
  @moduledoc "Manage the multi-day programme shown on an event's public ticket page."
  use DatemWeb, :live_view

  on_mount {DatemWeb.UserAuth, {:require_role, [:owner, :admin, :operator]}}

  alias Datem.NairobiTime
  alias Datem.Ticketing
  alias Datem.Ticketing.EventScheduleItem

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope
    event = Ticketing.get_event_for_scope!(scope, id)

    {:ok,
     socket
     |> assign(:event, event)
     |> assign(:show_form, false)
     |> assign(:editing_item, nil)
     |> assign(:items, Ticketing.list_schedule_items(scope, event))
     |> assign_form()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} max_width="max-w-full">
      <div class="mb-6 overflow-hidden rounded-xl border border-blue-100">
        <.pass_header
          icon="hero-calendar-days"
          title={"#{@event.name} · Schedule"}
          subtitle="Sessions and programme blocks shown when attendees open their ticket"
        >
          <.link navigate={~p"/events/#{@event.id}"}>
            <.button variant="secondary">Back to event</.button>
          </.link>
          <.button phx-click="new">Add session</.button>
        </.pass_header>

        <.table id="schedule-items" rows={@items}>
          <:col :let={i} label="When">
            <div class="whitespace-nowrap">
              <p class="font-medium text-gray-900">
                {NairobiTime.format(i.starts_at, "%d %b %Y")}
              </p>
              <p class="text-xs text-gray-500">
                {NairobiTime.format(i.starts_at, "%H:%M")}
                <%= if i.ends_at do %>
                  – {NairobiTime.format(i.ends_at, "%H:%M")}
                <% end %>
              </p>
            </div>
          </:col>
          <:col :let={i} label="Session">
            <p class="font-medium text-gray-900">{i.title}</p>
            <p :if={i.day_label} class="text-xs text-gray-500">{i.day_label}</p>
          </:col>
          <:col :let={i} label="Location">{i.location || "—"}</:col>
          <:col :let={i} label="Order">{i.position}</:col>
          <:col :let={i} label="Status">
            <.badge kind={(i.is_active && :success) || :neutral}>
              {(i.is_active && "Shown") || "Hidden"}
            </.badge>
          </:col>
          <:action :let={i}>
            <.link phx-click="edit" phx-value-id={i.id}>Edit</.link>
          </:action>
          <:action :let={i}>
            <.link phx-click="delete" phx-value-id={i.id} data-confirm="Remove this session?">
              Remove
            </.link>
          </:action>
          <:empty>
            No sessions yet. Add programme blocks for each day with the button above.
          </:empty>
        </.table>
      </div>

      <.modal :if={@show_form} id="schedule-modal" show on_cancel={JS.push("close_form")}>
        <.header>{if @editing_item, do: "Edit session", else: "Add session"}</.header>

        <.form for={@form} id="schedule_form" phx-submit="save" phx-change="validate">
          <.input field={@form[:title]} type="text" label="Title" required />
          <.input field={@form[:description]} type="textarea" label="Description (optional)" />
          <.input field={@form[:location]} type="text" label="Location / room (optional)" />
          <.input
            field={@form[:day_label]}
            type="text"
            label="Day label (optional)"
            placeholder="e.g. Day 1 — Opening"
          />
          <p class="-mt-2 text-xs text-gray-500">
            Shown as the heading for that calendar day on the public ticket. Leave blank to use the date.
          </p>
          <.input
            field={@form[:starts_at]}
            type="datetime-local"
            label="Starts at"
            value={datetime_local_value(@form[:starts_at].value)}
            required
          />
          <.input
            field={@form[:ends_at]}
            type="datetime-local"
            label="Ends at (optional)"
            value={datetime_local_value(@form[:ends_at].value)}
          />
          <.input field={@form[:position]} type="number" label="Order within the same start time" />
          <.input field={@form[:is_active]} type="checkbox" label="Show on the public ticket page" />

          <div class="mt-4 flex gap-3">
            <.button phx-disable-with="Saving...">
              {if @editing_item, do: "Save changes", else: "Add session"}
            </.button>
            <.button type="button" variant="secondary" phx-click="close_form">Cancel</.button>
          </div>
        </.form>
      </.modal>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("new", _params, socket) do
    {:noreply, socket |> assign(:editing_item, nil) |> assign(:show_form, true) |> assign_form()}
  end

  def handle_event("edit", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    item = Ticketing.get_schedule_item_for_scope!(scope, id)

    {:noreply,
     socket
     |> assign(:editing_item, item)
     |> assign(:show_form, true)
     |> assign_form(item)}
  end

  def handle_event("close_form", _params, socket) do
    {:noreply, socket |> assign(:show_form, false) |> assign(:editing_item, nil)}
  end

  def handle_event("validate", %{"event_schedule_item" => params}, socket) do
    item = socket.assigns.editing_item || %EventScheduleItem{}

    changeset =
      item
      |> Ticketing.change_schedule_item(parse_datetime_params(params))
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: "event_schedule_item"))}
  end

  def handle_event("save", %{"event_schedule_item" => params}, socket) do
    scope = socket.assigns.current_scope
    event = socket.assigns.event
    params = parse_datetime_params(params)

    result =
      case socket.assigns.editing_item do
        nil -> Ticketing.create_schedule_item(scope, event, params)
        item -> Ticketing.update_schedule_item(scope, item, params)
      end

    case result do
      {:ok, _item} ->
        {:noreply,
         socket
         |> put_flash(:info, "Saved.")
         |> assign(:show_form, false)
         |> assign(:editing_item, nil)
         |> assign(:items, Ticketing.list_schedule_items(scope, event))}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: "event_schedule_item"))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    event = socket.assigns.event
    item = Ticketing.get_schedule_item_for_scope!(scope, id)

    case Ticketing.delete_schedule_item(scope, item) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Removed.")
         |> assign(:items, Ticketing.list_schedule_items(scope, event))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Couldn't remove that.")}
    end
  end

  defp assign_form(socket, item \\ %EventScheduleItem{}),
    do:
      assign(
        socket,
        :form,
        to_form(Ticketing.change_schedule_item(item), as: "event_schedule_item")
      )

  defp parse_datetime_params(params) do
    params
    |> Map.update("starts_at", nil, &NairobiTime.parse_local_input/1)
    |> Map.update("ends_at", nil, &NairobiTime.parse_local_input/1)
  end

  defp datetime_local_value(%DateTime{} = dt), do: NairobiTime.local_input_value(dt)
  defp datetime_local_value(value) when is_binary(value), do: value
  defp datetime_local_value(_), do: nil
end
