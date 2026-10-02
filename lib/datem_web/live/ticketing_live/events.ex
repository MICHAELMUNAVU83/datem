defmodule DatemWeb.TicketingLive.Events do
  use DatemWeb, :live_view

  on_mount {DatemWeb.UserAuth, {:require_role, [:owner, :admin, :operator]}}

  alias Datem.Ticketing
  alias Datem.Ticketing.Event

  @impl true
  def render(assigns) do
    ~H"""
    def render(assigns) do
    ~H\"""
    <Layouts.app flash={@flash} current_scope={@current_scope} max_width="max-w-full">
      <div class="mb-6 overflow-hidden rounded-xl border border-blue-100">
        <.pass_header icon="hero-ticket" title="Events" subtitle="Create events and manage ticketing">
          <.button phx-click="new">Create an event</.button>
        </.pass_header>

        <.table id="events" rows={@events}>
          <:col :let={e} label="Name">
            <.link
              navigate={~p"/events/#{e.id}"}
              class="font-medium text-blue-600 hover:text-blue-700"
            >
              {e.name}
            </.link>
          </:col>
          <:col :let={e} label="Venue">{e.venue}</:col>
          <:col :let={e} label="Starts">
            {e.starts_at && Calendar.strftime(e.starts_at, "%Y-%m-%d %H:%M")}
          </:col>
          <:col :let={e} label="Status">
            <.badge kind={status_kind(e.status)}>{e.status}</.badge>
          </:col>
          <:action :let={e}>
            <.link phx-click="edit" phx-value-id={e.id}>Edit</.link>
          </:action>
          <:action :let={e}>
            <%= case e.status do %>
              <% "draft" -> %>
                <.link phx-click="set_status" phx-value-id={e.id} phx-value-status="published">Publish</.link>
              <% "published" -> %>
                <.link phx-click="set_status" phx-value-id={e.id} phx-value-status="closed">Close</.link>
              <% "closed" -> %>
                <.link phx-click="set_status" phx-value-id={e.id} phx-value-status="published">Reopen</.link>
            <% end %>
          </:action>
          <:empty>No events yet. Create one with the button above.</:empty>
        </.table>
      </div>

      <.modal :if={@show_form} id="event-modal" show on_cancel={JS.push("close_form")}>
        <.header>{if @editing_event, do: "Edit event", else: "Create an event"}</.header>

        <.form for={@form} id="event_form" phx-submit="save" phx-change="validate">
          <.input field={@form[:name]} type="text" label="Name" required />
          <.input field={@form[:venue]} type="text" label="Venue" />
          <.input field={@form[:description]} type="textarea" label="Description" />
          <.input field={@form[:starts_at]} type="datetime-local" label="Starts at" />
          <.input field={@form[:ends_at]} type="datetime-local" label="Ends at" />

          <div class="mt-4 grid grid-cols-2 gap-4">
            <.input field={@form[:brand_color_start]} type="color" label="Banner color (start)" />
            <.input field={@form[:brand_color_end]} type="color" label="Banner color (end)" />
          </div>
          <fieldset class="mt-4">
            <legend class="mb-1 block text-sm font-medium text-gray-700">
              Require attendees to provide
            </legend>
            <label
              :for={{label, value} <- attendee_field_options()}
              class="flex items-center gap-2 py-1"
            >
              <input
                type="checkbox"
                name="event[required_attendee_fields][]"
                value={value}
                checked={value in (@form[:required_attendee_fields].value || [])}
                class="size-4 rounded border-gray-300 accent-blue-600 focus:ring-blue-600"
              />
              <span class="text-sm text-gray-700">{label}</span>
            </label>
            <input type="hidden" name="event[required_attendee_fields][]" value="" />
          </fieldset>

          <div class="mt-4 flex gap-3">
            <.button phx-disable-with="Saving...">
              {if @editing_event, do: "Save changes", else: "Create event"}
            </.button>
            <.button type="button" variant="secondary" phx-click="close_form">Cancel</.button>
          </div>
        </.form>
      </.modal>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:show_form, false)
     |> assign(:editing_event, nil)
     |> assign_events()
     |> assign_form(Ticketing.change_event(%Event{}))}
  end

  @impl true
  def handle_event("validate", %{"event" => params}, socket) do
    changeset =
      current_event(socket)
      |> Ticketing.change_event(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"event" => params}, socket) do
    event = socket.assigns.editing_event

    result =
      if event,
        do: Ticketing.update_event(socket.assigns.current_scope, event, params),
        else: Ticketing.create_event(socket.assigns.current_scope, params)

    case result do
      {:ok, updated_event} ->
        warning =
          newly_required_fields_warning(socket.assigns.current_scope, event, updated_event)

        {:noreply,
         socket
         |> put_flash(:info, "Event saved.")
         |> then(fn s -> if warning, do: put_flash(s, :error, warning), else: s end)
         |> assign(:show_form, false)
         |> assign(:editing_event, nil)
         |> assign_events()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("set_status", %{"id" => id, "status" => status}, socket) do
    scope = socket.assigns.current_scope
    event = Ticketing.get_event_for_scope!(scope, id)

    case Ticketing.set_event_status(scope, event, status) do
      {:ok, _event} ->
        {:noreply, socket |> put_flash(:info, "Event status updated.") |> assign_events()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Couldn't update status.")}
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    event = Ticketing.get_event_for_scope!(socket.assigns.current_scope, id)

    {:noreply,
     socket
     |> assign(:editing_event, event)
     |> assign(:show_form, true)
     |> assign_form(Ticketing.change_event(event))}
  end

  def handle_event("new", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_event, nil)
     |> assign(:show_form, true)
     |> assign_form(Ticketing.change_event(%Event{}))}
  end

  def handle_event("close_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_form, false)
     |> assign(:editing_event, nil)
     |> assign_form(Ticketing.change_event(%Event{}))}
  end

  defp current_event(socket), do: socket.assigns.editing_event || %Event{}

  defp attendee_field_options do
    [
      {"Company", "company"},
      {"ID / passport number", "id_number"},
      {"Phone number", "phone_number"},
      {"Gender", "gender"},
      {"Date of birth", "dob"}
    ]
  end

  defp newly_required_fields_warning(_scope, nil, _updated_event), do: nil

  defp newly_required_fields_warning(scope, %{required_attendee_fields: before}, updated_event) do
    newly_required = updated_event.required_attendee_fields -- before

    counts =
      newly_required
      |> Enum.map(fn field ->
        {field, Ticketing.count_missing_field(scope, updated_event, field)}
      end)
      |> Enum.filter(fn {_field, count} -> count > 0 end)

    case counts do
      [] ->
        nil

      pairs ->
        "Heads up: " <>
          Enum.map_join(pairs, "; ", fn {f, c} ->
            "#{c} attendee(s) already registered without #{f}"
          end)
    end
  end

  defp assign_events(socket),
    do: assign(socket, :events, Ticketing.list_events(socket.assigns.current_scope))

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset, as: "event"))

  defp status_kind("published"), do: :success
  defp status_kind("closed"), do: :neutral
  defp status_kind(_), do: :info
end
