defmodule DatemWeb.TicketingLive.Events do
  use DatemWeb, :live_view

  on_mount {DatemWeb.UserAuth, {:require_role, [:owner, :admin, :operator]}}

  alias Datem.Ticketing
  alias Datem.Ticketing.Event

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Events
        <:subtitle>Create events and manage ticketing</:subtitle>
      </.header>

      <.table id="events" rows={@events}>
        <:col :let={e} label="Name">
          <.link navigate={~p"/events/#{e.id}"} class="font-medium text-blue-600 hover:text-blue-700">
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
        <:empty>No events yet. Create one below.</:empty>
      </.table>

      <div class="divider" />

      <.header>Create an event</.header>

      <.form for={@form} id="event_form" phx-submit="save" phx-change="validate">
        <.input field={@form[:name]} type="text" label="Name" required />
        <.input field={@form[:venue]} type="text" label="Venue" />
        <.input field={@form[:description]} type="textarea" label="Description" />
        <.input field={@form[:starts_at]} type="datetime-local" label="Starts at" />
        <.input field={@form[:ends_at]} type="datetime-local" label="Ends at" />

        <div class="mt-4">
          <.button phx-disable-with="Creating...">Create event</.button>
        </div>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign_events()
     |> assign_form(Ticketing.change_event(%Event{}))}
  end

  @impl true
  def handle_event("validate", %{"event" => params}, socket) do
    {:noreply,
     assign_form(socket, Ticketing.change_event(%Event{}, params) |> Map.put(:action, :validate))}
  end

  def handle_event("save", %{"event" => params}, socket) do
    case Ticketing.create_event(socket.assigns.current_scope, params) do
      {:ok, _event} ->
        {:noreply,
         socket
         |> put_flash(:info, "Event created.")
         |> assign_events()
         |> assign_form(Ticketing.change_event(%Event{}))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_events(socket),
    do: assign(socket, :events, Ticketing.list_events(socket.assigns.current_scope))

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset, as: "event"))

  defp status_kind("published"), do: :success
  defp status_kind("closed"), do: :neutral
  defp status_kind(_), do: :info
end
