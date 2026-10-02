defmodule DatemWeb.PassesLive.CarPasses do
  use DatemWeb, :live_view

  on_mount {DatemWeb.UserAuth, :require_authenticated}

  alias Datem.Passes
  alias Datem.Passes.CarPass
  alias Datem.Access
  alias Datem.Organizations
  alias Datem.NairobiTime

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    employees = Organizations.list_employees(scope)

    {:ok,
     socket
     |> assign(:show_form, false)
     |> assign(:vehicles, Access.list_vehicles(scope))
     |> assign(:employees, employees)
     |> assign(:current_employee, Enum.find(employees, &(&1.user_id == scope.user.id)))
     |> assign(:passes, Passes.list_car_passes(scope))
     |> assign(:decline_target_id, nil)
     |> assign(:mileage_target_id, nil)
|> assign(:mileage_action, nil)
|> assign(:mileage_value, "")
     |> assign(:decline_reason, "")
     |> assign_form()}
  end

  @impl true
 def render(assigns) do
  ~H"""
  <Layouts.app flash={@flash} current_scope={@current_scope} max_width="max-w-full">
    <div class="mb-6 overflow-hidden rounded-xl border border-blue-100">
      <.pass_header icon="hero-truck" title="Car Pass Management" subtitle="Track vehicle movements and mileage" count={length(@passes)}>
        <.button phx-click="new">+ New Car Pass</.button>
      </.pass_header>

      <.table id="car-passes" rows={@passes}>
        <:col :let={p} label="Serial">{p.serial}</:col>
        <:col :let={p} label="Vehicle">{p.vehicle && p.vehicle.plate}</:col>
        <:col :let={p} label="Carrying">{p.carrying}</:col>
        <:col :let={p} label="Date out">{NairobiTime.format(p.date_out, "%d %b %H:%M")}</:col>
        <:col :let={p} label="Date in">{NairobiTime.format(p.date_in, "%d %b %H:%M")}</:col>
        <:col :let={p} label="Mileage out/in">
          {p.mileage_out || "—"} / {p.mileage_in || "—"}
        </:col>
        <:col :let={p} label="Status">
          <.badge kind={status_kind(p.status)}>{p.status}</.badge>
        </:col>
        <:action :let={p}>
          <div
            :if={p.status == "pending" and @current_employee && p.approver_id == @current_employee.id}
            class="flex items-center gap-3"
          >
            <.link phx-click="approve" phx-value-id={p.id}>Approve</.link>
            <.link phx-click="show_decline" phx-value-id={p.id}>Decline</.link>
          </div>
          <.link :if={p.status == "approved"} phx-click="show_depart" phx-value-id={p.id}>Record departure</.link>
          <.link :if={p.status == "out"} phx-click="show_return" phx-value-id={p.id}>Record return</.link>
        </:action>
        <:empty>No car passes yet.</:empty>
      </.table>
    </div>

       <.modal :if={@show_form} id="car-pass-modal" show on_cancel={JS.push("close_form")}>
        <.header>New car pass</.header>

        <.form for={@form} id="car_pass_form" phx-submit="save" phx-change="validate">
          <.input field={@form[:serial]} type="text" label="Serial" required />
          <.input
            field={@form[:vehicle_id]}
            type="select"
            label="Vehicle"
            options={Enum.map(@vehicles, &{&1.plate, &1.id})}
            prompt="Select a vehicle"
          />
          <.input field={@form[:carrying]} type="text" label="Carrying (optional)" />
          <.input field={@form[:reason]} type="textarea" label="Reason" required />

          <div class="mt-4 flex gap-3">
            <.button phx-disable-with="Sending...">Send request</.button>
            <.button type="button" variant="secondary" phx-click="close_form">Cancel</.button>
          </div>
        </.form>
      </.modal>
    <.modal :if={@mileage_target_id} id="mileage-modal" show on_cancel={JS.push("close_mileage")}>
      <.header>{@mileage_action == :depart && "Record departure" || "Record return"}</.header>

      <form phx-submit="confirm_mileage">
        <label class="mb-1.5 block text-sm font-medium text-gray-700">Odometer reading</label>
        <input
          type="number"
          name="mileage"
          value={@mileage_value}
          phx-change="set_mileage"
          class="w-full rounded-lg border-gray-300 text-sm"
          required
        />

        <div class="mt-4 flex gap-3">
          <.button type="submit">Confirm</.button>
          <.button type="button" variant="secondary" phx-click="close_mileage">Cancel</.button>
        </div>
      </form>
    </.modal>
  </Layouts.app>
  """
end
  @impl true
  def handle_event("new", _params, socket),
    do: {:noreply, socket |> assign(:show_form, true) |> assign_form()}

  def handle_event("close_form", _params, socket),
    do: {:noreply, assign(socket, :show_form, false)}

  def handle_event("validate", %{"car_pass" => params}, socket) do
    changeset = %CarPass{} |> CarPass.changeset(params) |> Map.put(:action, :validate)
    {:noreply, assign(socket, :form, to_form(changeset, as: "car_pass"))}
  end

  def handle_event("save", %{"car_pass" => params}, socket) do
    scope = socket.assigns.current_scope
    requester = Enum.find(socket.assigns.employees, &(&1.user_id == scope.user.id))

    case requester && Passes.request_car_pass(scope, requester, params) do
      {:ok, _pass} ->
        {:noreply,
         socket
         |> put_flash(:info, "Request sent for approval.")
         |> assign(:show_form, false)
         |> assign(:passes, Passes.list_car_passes(scope))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: "car_pass"))}

      nil ->
        {:noreply, put_flash(socket, :error, "Your account isn't linked to a staff record yet.")}
    end
  end

  def handle_event("approve", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    pass = Enum.find(socket.assigns.passes, &(&1.id == String.to_integer(id)))

    case Passes.decide_car_pass(pass, "approved") do
      {:ok, _} ->
        {:noreply,
         socket |> put_flash(:info, "Approved.") |> assign(:passes, Passes.list_car_passes(scope))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Couldn't approve that.")}
    end
  end

  def handle_event("show_decline", %{"id" => id}, socket) do
    {:noreply,
     socket |> assign(:decline_target_id, String.to_integer(id)) |> assign(:decline_reason, "")}
  end

  def handle_event("close_decline", _params, socket) do
    {:noreply, socket |> assign(:decline_target_id, nil) |> assign(:decline_reason, "")}
  end

  def handle_event("set_decline_reason", %{"value" => reason}, socket) do
    {:noreply, assign(socket, :decline_reason, reason)}
  end

  def handle_event("confirm_decline", _params, socket) do
    scope = socket.assigns.current_scope
    pass = Enum.find(socket.assigns.passes, &(&1.id == socket.assigns.decline_target_id))

    case Passes.decide_car_pass(pass, "denied", socket.assigns.decline_reason) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Declined.")
         |> assign(:decline_target_id, nil)
         |> assign(:decline_reason, "")
         |> assign(:passes, Passes.list_car_passes(scope))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Couldn't decline that.")}
    end
  end
  def handle_event("show_depart", %{"id" => id}, socket) do
  {:noreply,
   socket
   |> assign(:mileage_target_id, String.to_integer(id))
   |> assign(:mileage_action, :depart)
   |> assign(:mileage_value, "")}
end

def handle_event("show_return", %{"id" => id}, socket) do
  {:noreply,
   socket
   |> assign(:mileage_target_id, String.to_integer(id))
   |> assign(:mileage_action, :return)
   |> assign(:mileage_value, "")}
end

def handle_event("close_mileage", _params, socket) do
  {:noreply, socket |> assign(:mileage_target_id, nil) |> assign(:mileage_action, nil)}
end

def handle_event("set_mileage", %{"mileage" => value}, socket) do
  {:noreply, assign(socket, :mileage_value, value)}
end

def handle_event("confirm_mileage", %{"mileage" => value}, socket) do
  scope = socket.assigns.current_scope
  pass = Passes.get_car_pass_for_scope!(scope, socket.assigns.mileage_target_id)
  mileage = String.to_integer(value)

  result =
    case socket.assigns.mileage_action do
      :depart -> Passes.record_car_departure(scope, pass, mileage)
      :return -> Passes.record_car_return(scope, pass, mileage)
    end

  case result do
    {:ok, _} ->
      {:noreply,
       socket
       |> put_flash(:info, "Recorded.")
       |> assign(:mileage_target_id, nil)
       |> assign(:mileage_action, nil)
       |> assign(:passes, Passes.list_car_passes(scope))}

    {:error, _} ->
      {:noreply, put_flash(socket, :error, "Couldn't record that.")}
  end
end




  defp assign_form(socket),
    do: assign(socket, :form, to_form(CarPass.changeset(%CarPass{}, %{}), as: "car_pass"))

  defp status_kind("approved"), do: :success
  defp status_kind("denied"), do: :danger
  defp status_kind("out"), do: :warning
  defp status_kind("returned"), do: :neutral
  defp status_kind(_), do: :info
end
