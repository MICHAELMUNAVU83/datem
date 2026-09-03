defmodule DatemWeb.TicketingLive.Join do
  @moduledoc """
  Public join-link registration: an attendee picks a ticket type, fills in
  their details, and receives a GSRN ticket QR — mirrors
  `DatemWeb.AccessLive.PreRegistration` for the ticketing module.
  """
  use DatemWeb, :live_view

  alias Datem.Ticketing
  alias Datem.Ticketing.Ticket
  alias Datem.GS1

  @impl true
  def render(%{event: nil} = assigns) do
    ~H"""
    <.public_shell title="Registration">
      <p class="text-gray-700">This registration link is invalid.</p>
    </.public_shell>
    """
  end

  def render(%{ticket: ticket} = assigns) when not is_nil(ticket) do
    ~H"""
    <.public_shell title={@event.name}>
      <p class="mb-4 text-gray-700">You're registered. Show this QR code at the door.</p>
      <div class="flex justify-center rounded-lg border border-gray-200 p-4">
        {Phoenix.HTML.raw(GS1.qr_svg(@ticket.gs1_identifier.digital_link, width: 220))}
      </div>
      <p :if={@ticket.attendee_email} class="mt-4 text-center text-sm text-gray-500">
        We've also emailed your ticket to {@ticket.attendee_email}.
      </p>
    </.public_shell>
    """
  end

  def render(assigns) do
    ~H"""
    <.public_shell title={@event.name}>
      <p class="mb-4 text-sm text-gray-600">{@event.venue}</p>

      <.form for={@form} id="join_form" phx-submit="save" phx-change="validate">
        <.input
          field={@form[:ticket_type_id]}
          type="select"
          label="Ticket type"
          options={Enum.map(@event.ticket_types, &{&1.name, &1.id})}
          required
        />
        <.input field={@form[:attendee_name]} type="text" label="Full name" required />
        <.input field={@form[:attendee_email]} type="email" label="Email" />

        <div class="mt-4">
          <.button phx-disable-with="Registering...">Get my ticket</.button>
        </div>
      </.form>
    </.public_shell>
    """
  end

  attr :title, :string, required: true
  slot :inner_block, required: true

  defp public_shell(assigns) do
    ~H"""
    <div class="flex min-h-screen items-center justify-center bg-gray-50 px-4">
      <div class="w-full max-w-md rounded-xl border border-gray-200 bg-white p-8 shadow-sm">
        <h1 class="mb-1 text-lg font-semibold text-gray-900">{@title}</h1>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    event = Ticketing.get_event_by_join_token(token)

    {:ok,
     socket
     |> assign(:event, event)
     |> assign(:ticket, nil)
     |> assign(:form, to_form(Ticket.changeset(%Ticket{}, %{}), as: "ticket"))}
  end

  @impl true
  def handle_event("validate", %{"ticket" => params}, socket) do
    changeset = %Ticket{} |> Ticket.changeset(params) |> Map.put(:action, :validate)
    {:noreply, assign(socket, :form, to_form(changeset, as: "ticket"))}
  end

  def handle_event("save", %{"ticket" => params}, socket) do
    event = socket.assigns.event

    ticket_type =
      Enum.find(event.ticket_types, &(&1.id == String.to_integer(params["ticket_type_id"])))

    case ticket_type && Ticketing.register_attendee(event, ticket_type, params) do
      {:ok, ticket} ->
        {:noreply, assign(socket, :ticket, ticket)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: "ticket"))}

      {:error, :sold_out} ->
        {:noreply, put_flash(socket, :error, "That ticket type is sold out.")}

      nil ->
        {:noreply, put_flash(socket, :error, "Please choose a ticket type.")}
    end
  end
end
