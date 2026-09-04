defmodule DatemWeb.AccessLive.Vehicles do
  use DatemWeb, :live_view

  on_mount {DatemWeb.UserAuth, {:require_role, [:owner, :admin, :operator]}}

  alias Datem.Access
  alias Datem.Access.Vehicle
  alias Datem.GS1

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Vehicles
        <:subtitle>Registered vehicles, each identified by a GIAI windscreen tag</:subtitle>
        <:actions>
          <.button phx-click="new">Register a vehicle</.button>
        </:actions>
      </.header>

      <.table id="vehicles" rows={@vehicles}>
        <:col :let={v} label="Plate">{v.plate}</:col>
        <:col :let={v} label="Make/Model">
          {[v.make, v.model] |> Enum.reject(&is_nil/1) |> Enum.join(" ")}
        </:col>
        <:col :let={v} label="GIAI"><code class="text-xs">{v.gs1_identifier.value}</code></:col>
        <:action :let={v}>
          <.link phx-click="show_qr" phx-value-id={v.id}>Show QR</.link>
        </:action>
        <:empty>No vehicles yet. Register one with the button above.</:empty>
      </.table>

      <div
        :if={@qr_vehicle}
        class="my-4 flex items-center gap-4 rounded-lg border border-gray-200 bg-white p-4"
      >
        {Phoenix.HTML.raw(GS1.qr_svg(@qr_vehicle.gs1_identifier.digital_link, width: 180))}
        <div class="text-sm text-gray-700">
          <p class="font-medium">{@qr_vehicle.plate}</p>
          <p>Print this for the windscreen tag.</p>
        </div>
      </div>

      <.modal :if={@show_form} id="vehicle-modal" show on_cancel={JS.push("close_form")}>
        <.header>Register a vehicle</.header>

        <.form for={@form} id="vehicle_form" phx-submit="save" phx-change="validate">
          <.input field={@form[:plate]} type="text" label="Plate" required />
          <.input field={@form[:make]} type="text" label="Make" />
          <.input field={@form[:model]} type="text" label="Model" />
          <div class="mt-4 flex gap-3">
            <.button phx-disable-with="Saving...">Register & issue QR</.button>
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
     |> assign(:qr_vehicle, nil)
     |> assign(:show_form, false)
     |> assign_vehicles()
     |> assign_form(Access.change_vehicle(%Vehicle{}))}
  end

  @impl true
  def handle_event("validate", %{"vehicle" => params}, socket) do
    {:noreply,
     assign_form(socket, Access.change_vehicle(%Vehicle{}, params) |> Map.put(:action, :validate))}
  end

  def handle_event("save", %{"vehicle" => params}, socket) do
    scope = socket.assigns.current_scope

    case Access.register_vehicle(scope, params) do
      {:ok, vehicle} ->
        {:noreply,
         socket
         |> put_flash(:info, "Vehicle registered.")
         |> assign(:qr_vehicle, vehicle)
         |> assign(:show_form, false)
         |> assign_vehicles()
         |> assign_form(Access.change_vehicle(%Vehicle{}))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("new", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_form, true)
     |> assign_form(Access.change_vehicle(%Vehicle{}))}
  end

  def handle_event("close_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_form, false)
     |> assign_form(Access.change_vehicle(%Vehicle{}))}
  end

  def handle_event("show_qr", %{"id" => id}, socket) do
    vehicle = Access.get_vehicle_for_scope!(socket.assigns.current_scope, id)
    {:noreply, assign(socket, :qr_vehicle, vehicle)}
  end

  defp assign_vehicles(socket),
    do: assign(socket, :vehicles, Access.list_vehicles(socket.assigns.current_scope))

  defp assign_form(socket, changeset),
    do: assign(socket, :form, to_form(changeset, as: "vehicle"))
end
