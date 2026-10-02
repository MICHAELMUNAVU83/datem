defmodule DatemWeb.AccessLive.Visitors do
  use DatemWeb, :live_view

  on_mount {DatemWeb.UserAuth, {:require_role, [:owner, :admin, :operator]}}

  alias Datem.Access
  alias Datem.Access.Visitor
  alias Datem.Organizations

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} max_width="max-w-full">
      <div class="mb-6 overflow-hidden rounded-xl border border-blue-100">
        <.pass_header
          icon="hero-identification"
          title="Visitors"
          subtitle="Register walk-ins, issue passes, or share a pre-registration link"
        >
          <.button phx-click="new">Register a walk-in</.button>
          <.button variant="secondary" phx-click="open_link_form">Create pre-registration link</.button>
          <.button variant="secondary" phx-click="open_checkin">Check in / out a visitor</.button>
          <.button
            :if={@current_employee}
            variant={(@show_mine && "primary") || "secondary"}
            phx-click="toggle_mine"
          >
            {(@show_mine && "Showing my visits") || "My visits"}
          </.button>
        </.pass_header>

        <div :if={@invite_url} class="border-b border-gray-200 bg-blue-50 p-4 text-sm">
          <p class="font-medium text-blue-900">Share this link with the visitor:</p>
          <code class="mt-1 block break-all text-blue-800">{@invite_url}</code>
        </div>

        <.table id="visitors"  rows={@paged_visitors}>
          <:col :let={v} label="Name">{v.name || "(pending)"}</:col>
          <:col :let={v} label="Contact">{v.contact}</:col>
          <:col :let={v} label="Email">{v.email}</:col>
          <:col :let={v} label="Company">{v.company}</:col>
          <:col :let={v} label="ID number">{v.id_number}</:col>
          <:col :let={v} label="Host">{v.host}</:col>
          <:col :let={v} label="Status">
            <.badge kind={status_kind(v.status)}>{v.status}</.badge>
          </:col>
          <:action :let={v}>
            <div
              :if={
                v.status == "awaiting_approval" and @current_employee &&
                  v.host_employee_id == @current_employee.id
              }
              class="flex items-center gap-3"
            >
              <.link phx-click="approve_visit" phx-value-id={v.id}>Approve</.link>
              <.link phx-click="decline_visit" phx-value-id={v.id} data-confirm="Decline this visit?">Decline</.link>
            </div>
            <.link
              :if={v.status in ["registered", "checked_in", "checked_out"]}
              navigate={~p"/visitors/#{v.id}"}
            >
              View pass
            </.link>
            <.button
              :if={v.status == "pending" and v.invite_token == nil}
              phx-click="issue_pass"
              phx-value-id={v.id}
            >
              Issue pass
            </.button>
            <.link
              :if={v.status in ["registered", "checked_in", "checked_out"]}
              phx-click="open_renew"
              phx-value-id={v.id}
            >
              Renew pass
            </.link>
          </:action>
          <:empty>No visitors yet. Register a walk-in with the button above.</:empty>
        </.table>
        <.pagination page={@page} total_pages={@total_pages} event="goto_page" />
      </div>

      <.modal :if={@show_form} id="visitor-modal" show on_cancel={JS.push("close_form")}>
        <.header>Register a walk-in visitor</.header>

        <.form for={@form} id="visitor_form" phx-submit="save" phx-change="validate">
          <.input field={@form[:name]} type="text" label="Name" required />
          <.input field={@form[:contact]} type="text" label="Contact (phone/email)" />
          <.input field={@form[:email]} type="email" label="Email" />
          <.input field={@form[:company]} type="text" label="Company" />
          <.input field={@form[:id_number]} type="text" label="ID / passport number" />
          <.input field={@form[:vehicle_reg]} type="text" label="Vehicle reg (if driving)" />
          <.input field={@form[:purpose]} type="textarea" label="Purpose of visit" />
          <.input
            field={@form[:host_employee_id]}
            type="select"
            label="Host"
            prompt="Select a host"
            options={Enum.map(@employees, &{&1.name, &1.id})}
          />

          <div class="mt-4">
            <label class="mb-1.5 block text-sm font-medium text-gray-700">Photo</label>
            <.live_file_input upload={@uploads.photo} class="text-sm" />
            <p :for={err <- upload_errors(@uploads.photo)} class="mt-1.5 text-sm text-red-600">
              {error_to_string(err)}
            </p>
          </div>

          <div class="mt-4 flex gap-3">
            <.button phx-disable-with="Saving...">Register & issue pass</.button>
            <.button type="button" variant="secondary" phx-click="close_form">Cancel</.button>
          </div>
        </.form>
      </.modal>
      <.modal :if={@show_checkin} id="checkin-modal" show on_cancel={JS.push("close_checkin")}>
        <.header>Check in / out a returning visitor</.header>

        <form phx-change="set_access_point" class="mb-4">
          <label class="mb-1.5 block text-sm font-medium text-gray-700">Access point</label>
          <select
            name="access_point_id"
            class="w-full rounded-lg border border-gray-300 px-3 py-2 text-base shadow-sm focus:border-blue-600 focus:ring-1 focus:ring-blue-600 sm:text-sm"
          >
            <option value="">Select where you're checking them in/out</option>
            <option
              :for={ap <- @access_points}
              value={ap.id}
              selected={@checkin_access_point_id == ap.id}
            >
              {ap.name}
            </option>
          </select>
        </form>

        <label class="mb-1.5 block text-sm font-medium text-gray-700">Search by name or ID</label>
        <input
          type="text"
          phx-keyup="search_visitors"
          phx-debounce="300"
          value={@checkin_query}
          placeholder="Start typing a name or ID number..."
          class="w-full rounded-lg border border-gray-300 px-3 py-2 text-base shadow-sm focus:border-blue-600 focus:ring-1 focus:ring-blue-600 sm:text-sm"
        />

        <ul class="mt-3 divide-y divide-gray-100">
          <li :for={v <- @checkin_results} class="flex items-center justify-between py-2">
            <div>
              <p class="text-sm font-medium text-gray-900">{v.name}</p>
              <p class="text-xs text-gray-500">
                {v.company} ·
                <.badge kind={status_kind(v.status)}>{v.status}</.badge>
              </p>
            </div>
            <.button
              :if={v.id != @checkin_no_pass_id}
              phx-click="do_checkin"
              phx-value-id={v.id}
              disabled={is_nil(@checkin_access_point_id)}
            >
              Check in / out
            </.button>
            <.button
              :if={v.id == @checkin_no_pass_id}
              variant="secondary"
              phx-click="renew_from_checkin"
              phx-value-id={v.id}
            >
              No active pass — renew?
            </.button>
          </li>
          <li :if={@checkin_query != "" and @checkin_results == []} class="py-2 text-sm text-gray-500">
            No matches found.
          </li>
        </ul>
      </.modal>
      <.modal :if={@renew_target} id="renew-modal" show on_cancel={JS.push("close_renew")}>
        <.header>Renew pass for {@renew_target.name}</.header>

        <form phx-change="set_renew_host">
          <label class="mb-1.5 block text-sm font-medium text-gray-700">Who are they visiting?</label>
          <select
            name="host_employee_id"
            class="w-full rounded-lg border border-gray-300 px-3 py-2 text-base shadow-sm focus:border-blue-600 focus:ring-1 focus:ring-blue-600 sm:text-sm"
          >
            <option value="">Same as before ({@renew_target.host})</option>
            <option :for={e <- @employees} value={e.id} selected={@renew_host_employee_id == e.id}>
              {e.name}
            </option>
          </select>
        </form>

        <div class="mt-4 flex gap-3">
          <.button phx-click="confirm_renew">Renew</.button>
          <.button type="button" variant="secondary" phx-click="close_renew">Cancel</.button>
        </div>
      </.modal>
      <.modal :if={@show_link_form} id="link-modal" show on_cancel={JS.push("close_link_form")}>
        <.header>Create a pre-registration link</.header>

        <form phx-submit="new_link">
          <label class="mb-1.5 block text-sm font-medium text-gray-700">Who is this visit for?</label>
          <select
            name="host_employee_id"
            class="w-full rounded-lg border border-gray-300 px-3 py-2 text-base shadow-sm focus:border-blue-600 focus:ring-1 focus:ring-blue-600 sm:text-sm"
            required
          >
            <option value="">Select a host</option>
            <option :for={e <- @employees} value={e.id}>{e.name}</option>
          </select>

          <div class="mt-4 flex gap-3">
            <.button type="submit">Create link</.button>
            <.button type="button" variant="secondary" phx-click="close_link_form">Cancel</.button>
          </div>
        </form>
      </.modal>
    </Layouts.app>
    """
  end


  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    employees = Organizations.list_employees(scope)

    {:ok,
     socket
     |> assign(:invite_url, nil)
     |> assign(:show_form, false)
     |> assign(:show_checkin, false)
     |> assign(:checkin_query, "")
     |> assign(:checkin_results, [])
     |> assign(:checkin_no_pass_id, nil)
     |> assign(:page, 1)
 |> assign(:per_page, 10)
     |> assign(:renew_target, nil)
     |> assign(:renew_host_employee_id, nil)
     |> assign(:checkin_access_point_id, nil)
     |> assign(:show_mine, false)
     |> assign(:access_points, Access.list_access_points(scope))
     |> assign(:show_link_form, false)
     |> assign(:employees, employees)
     |> assign(:current_employee, Enum.find(employees, &(&1.user_id == scope.user.id)))
     |> assign_visitors()
     |> assign_form(Access.change_visitor(%Visitor{}))
     |> allow_upload(:photo,
       accept: ~w(.jpg .jpeg .png),
       max_entries: 1,
       max_file_size: 5_000_000
     )}
  end

  @impl true
  def handle_event("validate", %{"visitor" => params}, socket) do
    {:noreply,
     assign_form(socket, Access.change_visitor(%Visitor{}, params) |> Map.put(:action, :validate))}
  end

  def handle_event("save", %{"visitor" => params}, socket) do
    scope = socket.assigns.current_scope
    params = put_host_name(params, socket.assigns.employees)

    with {:ok, visitor} <- Access.register_visitor(scope, params),
         {:ok, visitor} <- store_uploaded_photo(socket, scope, visitor),
         {:ok, _} <- Access.issue_pass(scope, visitor) do
      {:noreply,
       socket
       |> put_flash(:info, "Visitor registered and pass issued.")
       |> assign(:show_form, false)
       |> assign_visitors()
       |> assign_form(Access.change_visitor(%Visitor{}))}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("open_renew", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    visitor = Access.get_visitor_for_scope!(scope, id)
    {:noreply, socket |> assign(:renew_target, visitor) |> assign(:renew_host_employee_id, nil)}
  end

  def handle_event("close_renew", _params, socket) do
    {:noreply, socket |> assign(:renew_target, nil) |> assign(:renew_host_employee_id, nil)}
  end

  def handle_event("set_renew_host", %{"host_employee_id" => id}, socket) do
    {:noreply,
     assign(socket, :renew_host_employee_id, (id == "" && nil) || String.to_integer(id))}
  end
  def handle_event("goto_page", %{"page" => page}, socket) do
  {:noreply, assign(socket, :page, String.to_integer(page)) |> clamp_page()}
end

  def handle_event("open_link_form", _params, socket), do: {:noreply, assign(socket, :show_link_form, true)}
def handle_event("close_link_form", _params, socket), do: {:noreply, assign(socket, :show_link_form, false)}

def handle_event("new_link", %{"host_employee_id" => id}, socket) do
  scope = socket.assigns.current_scope
  employee = Enum.find(socket.assigns.employees, &(&1.id == String.to_integer(id)))

  case employee && Access.create_pre_registration(scope, employee) do
    {:ok, visitor} ->
      {:noreply,
       socket
       |> assign(:invite_url, url(~p"/visit/#{visitor.invite_token}"))
       |> assign(:show_link_form, false)
       |> assign_visitors()}

    _ ->
      {:noreply, put_flash(socket, :error, "Couldn't create a pre-registration link.")}
  end
end

 def handle_event("toggle_mine", _params, socket) do
  {:noreply,
   socket
   |> assign(:show_mine, !socket.assigns.show_mine)
   |> assign(:page, 1)
   |> assign_displayed_visitors()}
end

  def handle_event("approve_visit", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    visitor = Access.get_visitor_for_scope!(scope, id)

    case Access.approve_visitor(scope, visitor) do
      {:ok, _} -> {:noreply, socket |> put_flash(:info, "Approved.") |> assign_visitors()}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Couldn't approve that visit.")}
    end
  end

  def handle_event("decline_visit", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    visitor = Access.get_visitor_for_scope!(scope, id)

    case Access.deny_visitor(scope, visitor) do
      {:ok, _} -> {:noreply, socket |> put_flash(:info, "Declined.") |> assign_visitors()}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Couldn't decline that visit.")}
    end
  end

  def handle_event("confirm_renew", _params, socket) do
    scope = socket.assigns.current_scope
    visitor = socket.assigns.renew_target

    attrs =
      case socket.assigns.renew_host_employee_id do
        nil ->
          %{}

        employee_id ->
          employee = Enum.find(socket.assigns.employees, &(&1.id == employee_id))
          %{"host_employee_id" => employee_id, "host" => employee.name}
      end

    case Access.renew_pass(scope, visitor, attrs) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Pass renewed for #{visitor.name}.")
         |> assign(:renew_target, nil)
         |> assign_visitors()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Couldn't renew that pass.")}
    end
  end

  def handle_event("renew_pass", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    visitor = Access.get_visitor_for_scope!(scope, id)

    case Access.renew_pass(scope, visitor) do
      {:ok, _} ->
        {:noreply,
         socket |> put_flash(:info, "Pass renewed for #{visitor.name}.") |> assign_visitors()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Couldn't renew that pass.")}
    end
  end

  def handle_event("open_checkin", _params, socket),
    do: {:noreply, assign(socket, :show_checkin, true)}

  def handle_event("close_checkin", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_checkin, false)
     |> assign(:checkin_query, "")
     |> assign(:checkin_results, [])
     |> assign(:checkin_access_point_id, nil)}
  end

  def handle_event("set_access_point", %{"access_point_id" => id}, socket) do
    {:noreply,
     assign(socket, :checkin_access_point_id, (id == "" && nil) || String.to_integer(id))}
  end

  def handle_event("search_visitors", %{"value" => query}, socket) do
    scope = socket.assigns.current_scope
    results = if query == "", do: [], else: Access.search_visitors(scope, query)

    {:noreply, socket |> assign(:checkin_query, query) |> assign(:checkin_results, results)}
  end

  def handle_event("do_checkin", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    visitor = Access.get_visitor_for_scope!(scope, id)

    access_point =
      Enum.find(socket.assigns.access_points, &(&1.id == socket.assigns.checkin_access_point_id))

    case access_point && Access.manual_scan_visitor(scope, visitor, access_point, scope.user) do
      {:ok, _log, direction} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{visitor.name} checked #{direction}.")
         |> assign(:show_checkin, false)
         |> assign(:checkin_query, "")
         |> assign(:checkin_results, [])
         |> assign_visitors()}

      {:error, :no_active_pass} ->
        {:noreply, put_flash(socket, :error, "#{visitor.name} has no active pass to scan.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Couldn't check that visitor in/out.")}

      nil ->
        {:noreply, put_flash(socket, :error, "Choose an access point first.")}
    end
  end

  def handle_event("new", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_form, true)
     |> assign_form(Access.change_visitor(%Visitor{}))}
  end

  def handle_event("close_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_form, false)
     |> assign_form(Access.change_visitor(%Visitor{}))}
  end

  def handle_event("issue_pass", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    visitor = Access.get_visitor_for_scope!(scope, id)

    case Access.issue_pass(scope, visitor) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Pass issued.") |> assign_visitors()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Couldn't issue a pass for that visitor.")}
    end
  end



  defp assign_form(socket, changeset),
    do: assign(socket, :form, to_form(changeset, as: "visitor"))

  defp store_uploaded_photo(socket, scope, visitor) do
    paths =
      consume_uploaded_entries(socket, :photo, fn %{path: tmp_path}, entry ->
        filename =
          "#{visitor.id}-#{System.system_time(:millisecond)}#{Path.extname(entry.client_name)}"

        dest = Path.join([:code.priv_dir(:datem), "static", "uploads", "visitors", filename])
        File.cp!(tmp_path, dest)
        {:ok, "/uploads/visitors/#{filename}"}
      end)

    case paths do
      [path] -> Access.store_visitor_photo(scope, visitor, path)
      [] -> {:ok, visitor}
    end
  end



  defp put_host_name(%{"host_employee_id" => id} = params, employees) when id not in [nil, ""] do
    case Enum.find(employees, &(to_string(&1.id) == id)) do
      nil -> params
      employee -> Map.put(params, "host", employee.name)
    end
  end

  defp assign_visitors(socket) do
    socket
    |> assign(:visitors, Access.list_visitors(socket.assigns.current_scope))
    |> assign_displayed_visitors()
  end

  defp assign_displayed_visitors(socket) do
  visitors =
    if socket.assigns.show_mine and socket.assigns.current_employee do
      employee_id = socket.assigns.current_employee.id
      Enum.filter(socket.assigns.visitors, &(&1.host_employee_id == employee_id))
    else
      socket.assigns.visitors
    end

  total_pages = max(ceil(length(visitors) / socket.assigns.per_page), 1)

  socket
  |> assign(:displayed_visitors, visitors)
  |> assign(:total_pages, total_pages)
  |> clamp_page()
  |> assign_paged_visitors()
end

defp assign_paged_visitors(socket) do
  %{displayed_visitors: visitors, page: page, per_page: per_page} = socket.assigns
  paged = Enum.slice(visitors, (page - 1) * per_page, per_page)
  assign(socket, :paged_visitors, paged)
end

defp clamp_page(socket) do
  page = min(max(socket.assigns.page, 1), socket.assigns.total_pages)
  socket |> assign(:page, page) |> assign_paged_visitors()
end

  def pagination(assigns) do
    ~H"""
    <nav :if={@total_pages > 1} class="mt-4 flex items-center justify-center gap-2" aria-label="Pagination">
      <button
        :if={@page > 1}
        type="button"
        phx-click={@event}
        phx-value-page={@page - 1}
        class="rounded border px-3 py-1 text-sm"
      >
        Previous
      </button>
      <span class="text-sm text-gray-600">Page {@page} of {@total_pages}</span>
      <button
        :if={@page < @total_pages}
        type="button"
        phx-click={@event}
        phx-value-page={@page + 1}
        class="rounded border px-3 py-1 text-sm"
      >
        Next
      </button>
    </nav>
    """
  end



  defp error_to_string(:too_large), do: "File is too large (max 5MB)."
  defp error_to_string(:not_accepted), do: "Only JPG or PNG photos are accepted."
  defp error_to_string(_), do: "Couldn't upload that file."

  defp status_kind("registered"), do: :info
  defp status_kind("checked_in"), do: :success
  defp status_kind("checked_out"), do: :neutral
  defp status_kind("denied"), do: :danger
  defp status_kind(_), do: :neutral
end
