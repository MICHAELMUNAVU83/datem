defmodule DatemWeb.PassesLive.ItemPasses do
  use DatemWeb, :live_view

  on_mount {DatemWeb.UserAuth, :require_authenticated}

  alias Datem.Passes
  alias Datem.Passes.ItemPass
  alias Datem.Organizations
  alias Datem.NairobiTime

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    employees = Organizations.list_employees(scope)

    {:ok,
     socket
     |> assign(:show_form, false)
     |> assign(:employees, Organizations.list_employees(scope))
     |> assign(:passes, Passes.list_item_passes(scope))
     |> assign(:current_employee, Enum.find(employees, &(&1.user_id == scope.user.id)))
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
                <.icon name="hero-archive-box" class="size-5" /> Item passes
              </p>
              <p class="text-sm text-blue-700">Requests to take a company asset off-site</p>
            </div>
            <div class="rounded-lg bg-white px-4 py-2 text-center shadow-sm">
              <p class="text-xl font-semibold text-blue-900">{length(@passes)}</p>
              <p class="text-xs text-blue-600">Total Passes</p>
            </div>
          </div>

          <div class="flex justify-end border-b border-gray-200 bg-white px-6 py-3">
            <.button phx-click="new">Request an item pass</.button>
          </div>
        </div>

        <.table id="item-passes" rows={@passes}>
          <:col :let={p} label="Item">{p.item_name}</:col>
          <:col :let={p} label="Requested by">{p.requested_by.name}</:col>
          <:col :let={p} label="Type">{(p.returnable && "Returnable") || "Non-returnable"}</:col>
          <:col :let={p} label="Reason">{p.reason}</:col>
          <:col :let={p} label="Status">
            <.badge kind={status_kind(p.status)}>{p.status}</.badge>
          </:col>
          <:col :let={p} label="Returned">
            <span :if={p.returnable}>
              {(p.returned_at && NairobiTime.format(p.returned_at, "%d %b %H:%M")) || "—"}
            </span>
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
            <.link
              :if={p.status == "approved" and p.returnable and is_nil(p.returned_at)}
              phx-click="mark_returned"
              phx-value-id={p.id}
              data-confirm={"Mark #{p.item_name} as returned?"}
            >
              Mark returned
            </.link>
          </:action>
          <:empty>No item passes yet.</:empty>
        </.table>
      </div>
      <.modal :if={@show_form} id="item-pass-modal" show on_cancel={JS.push("close_form")}>
        <.header>Request an item pass</.header>

        <.form for={@form} id="item_pass_form" phx-submit="save" phx-change="validate">
          <.input field={@form[:item_name]} type="text" label="Item" required />
          <.input field={@form[:description]} type="textarea" label="Description (optional)" />
          <.input field={@form[:returnable]} type="checkbox" label="This item will be returned" />
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

  def handle_event("validate", %{"item_pass" => params}, socket) do
    changeset = %ItemPass{} |> ItemPass.changeset(params) |> Map.put(:action, :validate)
    {:noreply, assign(socket, :form, to_form(changeset, as: "item_pass"))}
  end

  def handle_event("save", %{"item_pass" => params}, socket) do
    scope = socket.assigns.current_scope
    requester = current_employee(scope, socket.assigns.employees)

    case requester && Passes.request_item_pass(scope, requester, params) do
      {:ok, _pass} ->
        {:noreply,
         socket
         |> put_flash(:info, "Request sent for approval.")
         |> assign(:show_form, false)
         |> assign(:passes, Passes.list_item_passes(scope))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: "item_pass"))}

      nil ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Your account isn't linked to a staff record yet — ask an admin, or use \"This is me\" on the Staff page."
         )}
    end
  end

  def handle_event("mark_returned", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    pass = Passes.get_item_pass_for_scope!(scope, id)

    case Passes.mark_item_returned(scope, pass) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Marked as returned.")
         |> assign(:passes, Passes.list_item_passes(scope))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Couldn't update that.")}
    end
  end

  def handle_event("approve", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    pass = Enum.find(socket.assigns.passes, &(&1.id == String.to_integer(id)))

    case Passes.decide_item_pass(pass, "approved") do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Approved.")
         |> assign(:passes, Passes.list_item_passes(scope))}

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

    case Passes.decide_item_pass(pass, "denied", socket.assigns.decline_reason) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Declined.")
         |> assign(:decline_target_id, nil)
         |> assign(:decline_reason, "")
         |> assign(:passes, Passes.list_item_passes(scope))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Couldn't decline that.")}
    end
  end

  defp current_employee(scope, employees),
    do: Enum.find(employees, &(&1.user_id == scope.user.id))

  defp assign_form(socket),
    do: assign(socket, :form, to_form(ItemPass.changeset(%ItemPass{}, %{}), as: "item_pass"))

  defp status_kind("approved"), do: :success
  defp status_kind("denied"), do: :danger
  defp status_kind(_), do: :info
end
