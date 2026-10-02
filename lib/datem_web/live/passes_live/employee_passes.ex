defmodule DatemWeb.PassesLive.EmployeePasses do
  use DatemWeb, :live_view

  on_mount {DatemWeb.UserAuth, :require_authenticated}

  alias Datem.Passes
  alias Datem.Passes.EmployeePass
  alias Datem.Organizations
  alias Datem.NairobiTime

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    employees = Organizations.list_employees(scope)

    {:ok,
     socket
     |> assign(:show_form, false)
     |> assign(:employees, employees)
     |> assign(:current_employee, Enum.find(employees, &(&1.user_id == scope.user.id)))
     |> assign(:passes, Passes.list_employee_passes(scope))
     |> assign(:decline_target_id, nil)
     |> assign(:decline_reason, "")
     |> assign_form()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} max_width="max-w-full">
      <div class="mb-6 overflow-hidden rounded-xl border border-blue-100">
        <div class="overflow-hidden rounded-xl border border-blue-100">
          <div class="flex items-center justify-between bg-blue-50 px-6 py-5">
            <div>
              <p class="flex items-center gap-2 text-lg font-semibold text-blue-900">
                <.icon name="hero-arrow-right-start-on-rectangle" class="size-5" /> Exit passes
              </p>
              <p class="text-sm text-blue-700">Requests to step out, and their approval status</p>
            </div>
            <div class="rounded-lg bg-white px-4 py-2 text-center shadow-sm">
              <p class="text-xl font-semibold text-blue-900">{length(@passes)}</p>
              <p class="text-xs text-blue-600">Total Passes</p>
            </div>
          </div>

          <div class="flex justify-end border-b border-gray-200 bg-white px-6 py-3">
            <.button phx-click="new">Request an exit pass</.button>
          </div>
        </div>

        <.table id="employee-passes" rows={@passes}>
          <:col :let={p} label="For">{p.employee.name}</:col>
          <:col :let={p} label="Requested by">{p.requested_by.name}</:col>
          <:col :let={p} label="Reason">{p.reason}</:col>
          <:col :let={p} label="Requested">{NairobiTime.format(p.inserted_at, "%d %b %H:%M")}</:col>
          <:col :let={p} label="From – To">
            {NairobiTime.format(p.expected_departure_at, "%H:%M")} – {NairobiTime.format(
              p.expected_return_at,
              "%H:%M"
            )}
          </:col>
          <:col :let={p} label="Status">
            <.badge kind={status_kind(p.status)}>{p.status}</.badge>
          </:col>
          <:action :let={p}>
            <div
              :if={
                p.status == "pending" and @current_employee && p.approver_id == @current_employee.id
              }
              class="flex items-center gap-3"
            >
              <.link phx-click="approve" phx-value-id={p.id}>Approve</.link>
              <.link phx-click="show_decline" phx-value-id={p.id}>Decline</.link>
            </div>
          </:action>
          <:empty>No exit passes yet.</:empty>
        </.table>
      </div>
      <.modal :if={@decline_target_id} id="decline-modal" show on_cancel={JS.push("close_decline")}>
        <.header>Reason for declining</.header>

        <textarea
          phx-blur="set_decline_reason"
          name="reason"
          class="w-full rounded-lg border-gray-300 text-sm"
          rows="3"
          placeholder="Optional, but helpful for the requester"
        >{@decline_reason}</textarea>

        <div class="mt-4 flex gap-3">
          <.button variant="danger" phx-click="confirm_decline">Confirm decline</.button>
          <.button type="button" variant="secondary" phx-click="close_decline">Cancel</.button>
        </div>
      </.modal>

      <.modal :if={@show_form} id="pass-modal" show on_cancel={JS.push("close_form")}>
        <.header>Request an exit pass</.header>

        <.form for={@form} id="pass_form" phx-submit="save" phx-change="validate">
          <.input
            field={@form[:employee_id]}
            type="select"
            label="Who is leaving"
            options={Enum.map(@employees, &{&1.name, &1.id})}
            required
          />
          <.input field={@form[:for_self]} type="checkbox" label="I am requesting this for myself" />
          <.input field={@form[:expected_departure_at]} type="datetime-local" label="From" />
          <.input field={@form[:expected_return_at]} type="datetime-local" label="Expected back" />
          <.input field={@form[:reason]} type="textarea" label="Reason" required />

          <div class="mt-4 flex gap-3">
            <.button phx-disable-with="Sending...">Send request</.button>
            <.button type="button" variant="secondary" phx-click="close_form">Cancel</.button>
          </div>
        </.form>
      </.modal>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("new", _params, socket),
    do: {:noreply, socket |> assign(:show_form, true) |> assign_form()}

  def handle_event("close_form", _params, socket),
    do: {:noreply, assign(socket, :show_form, false)}

  def handle_event("validate", %{"employee_pass" => params}, socket) do
    changeset = %EmployeePass{} |> EmployeePass.changeset(params) |> Map.put(:action, :validate)
    {:noreply, assign(socket, :form, to_form(changeset, as: "employee_pass"))}
  end

  def handle_event("save", %{"employee_pass" => params}, socket) do
    params =
      params
      |> Map.update("expected_departure_at", nil, &Datem.NairobiTime.parse_local_input/1)
      |> Map.update("expected_return_at", nil, &Datem.NairobiTime.parse_local_input/1)

    scope = socket.assigns.current_scope

    employee =
      Enum.find(socket.assigns.employees, &(&1.id == String.to_integer(params["employee_id"])))

    requester = current_employee(scope, socket.assigns.employees)

    case employee && requester && Passes.request_employee_pass(scope, employee, requester, params) do
      {:ok, _pass} ->
        {:noreply,
         socket
         |> put_flash(:info, "Request sent for approval.")
         |> assign(:show_form, false)
         |> assign(:passes, Passes.list_employee_passes(scope))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: "employee_pass"))}

      nil ->
        {:noreply, put_flash(socket, :error, "Couldn't identify who's requesting this.")}
    end
  end

  def handle_event("approve", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    pass = Enum.find(socket.assigns.passes, &(&1.id == String.to_integer(id)))

    case Passes.decide_employee_pass(pass, "approved") do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Approved.")
         |> assign(:passes, Passes.list_employee_passes(scope))}

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

    case Passes.decide_employee_pass(pass, "denied", socket.assigns.decline_reason) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Declined.")
         |> assign(:decline_target_id, nil)
         |> assign(:decline_reason, "")
         |> assign(:passes, Passes.list_employee_passes(scope))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Couldn't decline that.")}
    end
  end

  defp current_employee(scope, employees),
    do: Enum.find(employees, &(&1.user_id == scope.user.id))

  defp assign_form(socket),
    do:
      assign(
        socket,
        :form,
        to_form(EmployeePass.changeset(%EmployeePass{}, %{}), as: "employee_pass")
      )

  defp status_kind("approved"), do: :success
  defp status_kind("denied"), do: :danger
  defp status_kind(_), do: :info
end
