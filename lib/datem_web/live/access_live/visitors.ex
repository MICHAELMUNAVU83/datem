defmodule DatemWeb.AccessLive.Visitors do
  use DatemWeb, :live_view

  on_mount {DatemWeb.UserAuth, {:require_role, [:owner, :admin, :operator]}}

  alias Datem.Access
  alias Datem.Access.Visitor

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Visitors
        <:subtitle>Register walk-ins, issue passes, or share a pre-registration link</:subtitle>
        <:actions>
          <.button phx-click="new">Register a walk-in</.button>
          <.button phx-click="new_link">Create pre-registration link</.button>
        </:actions>
      </.header>

      <div :if={@invite_url} class="mb-4 rounded-lg border border-blue-200 bg-blue-50 p-4 text-sm">
        <p class="font-medium text-blue-900">Share this link with the visitor:</p>
        <code class="mt-1 block break-all text-blue-800">{@invite_url}</code>
      </div>

      <.table id="visitors" rows={@visitors}>
        <:col :let={v} label="Name">{v.name || "(pending)"}</:col>
        <:col :let={v} label="Company">{v.company}</:col>
        <:col :let={v} label="Host">{v.host}</:col>
        <:col :let={v} label="Status">
          <.badge kind={status_kind(v.status)}>{v.status}</.badge>
        </:col>
        <:action :let={v}>
          <.link
            :if={v.status == "registered" or v.status == "checked_in" or v.status == "checked_out"}
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
        </:action>
        <:empty>No visitors yet. Register a walk-in with the button above.</:empty>
      </.table>

      <.modal :if={@show_form} id="visitor-modal" show on_cancel={JS.push("close_form")}>
        <.header>Register a walk-in visitor</.header>

        <.form for={@form} id="visitor_form" phx-submit="save" phx-change="validate">
          <.input field={@form[:name]} type="text" label="Name" required />
          <.input field={@form[:contact]} type="text" label="Contact (phone/email)" />
          <.input field={@form[:company]} type="text" label="Company" />
          <.input field={@form[:host]} type="text" label="Host" />

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
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:invite_url, nil)
     |> assign(:show_form, false)
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

  def handle_event("new_link", _params, socket) do
    scope = socket.assigns.current_scope
    host = (scope.user && scope.user.email) || "reception"

    case Access.create_pre_registration(scope, host) do
      {:ok, visitor} ->
        {:noreply,
         socket
         |> assign(:invite_url, url(~p"/visit/#{visitor.invite_token}"))
         |> assign_visitors()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Couldn't create a pre-registration link.")}
    end
  end

  defp assign_visitors(socket),
    do: assign(socket, :visitors, Access.list_visitors(socket.assigns.current_scope))

  defp assign_form(socket, changeset),
    do: assign(socket, :form, to_form(changeset, as: "visitor"))

  # Stored on local disk under priv/static/uploads for now — swap for
  # object storage with signed URLs before handling real visitor PII.
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

  defp error_to_string(:too_large), do: "File is too large (max 5MB)."
  defp error_to_string(:not_accepted), do: "Only JPG or PNG photos are accepted."
  defp error_to_string(_), do: "Couldn't upload that file."

  defp status_kind("registered"), do: :info
  defp status_kind("checked_in"), do: :success
  defp status_kind("checked_out"), do: :neutral
  defp status_kind("denied"), do: :danger
  defp status_kind(_), do: :neutral
end
