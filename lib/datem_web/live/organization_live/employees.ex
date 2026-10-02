defmodule DatemWeb.OrganizationLive.Employees do
  use DatemWeb, :live_view

  on_mount {DatemWeb.UserAuth, {:require_role, [:owner, :admin]}}

  alias Datem.Organizations
  alias Datem.Organizations.Employee

  @impl true
def render(assigns) do
  ~H"""
  <Layouts.app flash={@flash} current_scope={@current_scope} max_width="max-w-full">
    <div class="mb-6 overflow-hidden rounded-xl border border-blue-100">
      <.pass_header icon="hero-user-group" title="Staff" subtitle="People visitors can be hosted by.">
        <.button phx-click="new">Add staff member</.button>
      </.pass_header>

      <.table id="employees" rows={@employees}>
        <:col :let={e} label="Name">{e.name}</:col>
        <:col :let={e} label="Department">{e.department}</:col>
        <:col :let={e} label="Email">{e.email}</:col>
        <:col :let={e} label="Account">
          <.badge kind={(e.user_id && :success) || :neutral}>
            {(e.user_id && "Linked") || "Directory only"}
          </.badge>
        </:col>
        <:action :let={e}>
          <.link phx-click="edit" phx-value-id={e.id}>Edit</.link>
        </:action>
        <:action :let={e}>
          <.link phx-click="delete" phx-value-id={e.id} data-confirm="Remove this staff member?">
            Remove
          </.link>
        </:action>
        <:empty>No staff yet.</:empty>
      </.table>
    </div>

    <.modal :if={@show_form} id="employee-modal" show on_cancel={JS.push("close_form")}>
      <.header>{if @editing_employee, do: "Edit staff member", else: "Add staff member"}</.header>

      <.form for={@form} id="employee_form" phx-submit="save" phx-change="validate">
        <.input field={@form[:name]} type="text" label="Name" required />
        <.input field={@form[:department]} type="text" label="Department" />
        <.input field={@form[:email]} type="email" label="Email" />
        <.input field={@form[:phone]} type="text" label="Phone" />
        <.input
          field={@form[:user_id]}
          type="select"
          label="Linked account (optional)"
          prompt="No account linked"
          options={Enum.map(@members, &{&1.user.email, &1.user.id})}
        />
        <.input
          field={@form[:head_employee_id]}
          type="select"
          label="Reports to (approves their passes)"
          prompt="No head assigned"
          options={Enum.map(@employees, &{&1.name, &1.id})}
        />

        <div class="mt-4 flex gap-3">
          <.button phx-disable-with="Saving...">
            {if @editing_employee, do: "Save changes", else: "Add staff member"}
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
     |> assign(:editing_employee, nil)
     |> assign_employees()
     |> assign(:members, Organizations.list_members(socket.assigns.current_scope))
     |> assign_form(Organizations.change_employee(%Employee{}))}
  end

  @impl true
  def handle_event("edit", %{"id" => id}, socket) do
    employee = Organizations.get_employee_for_scope!(socket.assigns.current_scope, id)

    {:noreply,
     socket
     |> assign(:show_form, true)
     |> assign(:editing_employee, employee)
     |> assign_form(Organizations.change_employee(employee))}
  end

  @impl true
  def handle_event("close_form", _params, socket) do
    {:noreply, socket |> assign(:show_form, false) |> assign(:editing_employee, nil)}
  end

  @impl true
  def handle_event("validate", %{"employee" => params}, socket) do
    base = socket.assigns.editing_employee || %Employee{}

    changeset =
      base |> Organizations.change_employee(params) |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  @impl true
  def handle_event("save", %{"employee" => params}, socket) do
    save_employee(socket, socket.assigns.editing_employee, params)
  end

  def handle_event("new", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_form, true)
     |> assign(:editing_employee, nil)
     |> assign_form(Organizations.change_employee(%Employee{}))}
  end
    def handle_event("delete", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    employee = Organizations.get_employee_for_scope!(scope, id)

    case Organizations.delete_employee(scope, employee) do
      {:ok, _} -> {:noreply, socket |> put_flash(:info, "Removed.") |> assign_employees()}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Couldn't remove that staff member.")}
    end
  end

  defp save_employee(socket, nil, params) do
    case Organizations.create_employee(socket.assigns.current_scope, params) do
      {:ok, _employee} ->
        {:noreply,
         socket
         |> put_flash(:info, "Staff member added.")
         |> assign(:show_form, false)
         |> assign(:editing_employee, nil)
         |> assign_employees()
         |> assign_form(Organizations.change_employee(%Employee{}))}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_employee(socket, employee, params) do
    case Organizations.update_employee(socket.assigns.current_scope, employee, params) do
      {:ok, _employee} ->
        {:noreply,
         socket
         |> put_flash(:info, "Staff member updated.")
         |> assign(:show_form, false)
         |> assign(:editing_employee, nil)
         |> assign_employees()
         |> assign_form(Organizations.change_employee(%Employee{}))}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end



  defp assign_employees(socket),
    do: assign(socket, :employees, Organizations.list_employees(socket.assigns.current_scope))

  defp assign_form(socket, changeset),
    do: assign(socket, :form, to_form(changeset, as: "employee"))
end
