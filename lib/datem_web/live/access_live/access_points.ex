defmodule DatemWeb.AccessLive.AccessPoints do
  use DatemWeb, :live_view

  on_mount {DatemWeb.UserAuth, {:require_role, [:owner, :admin]}}

  alias Datem.Access
  alias Datem.Access.AccessPoint

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} max_width="max-w-full">
      <div class="mb-6 overflow-hidden rounded-xl border border-blue-100">
        <.pass_header
          icon="hero-map-pin"
          title="Access points"
          subtitle="Gates and checkpoints, each identified by a GLN extension"
        >
          <.button :if={@sites != []} phx-click="new">Add an access point</.button>
        </.pass_header>

        <p :if={@sites == []} class="mb-4 text-sm text-gray-500">
          Add a site first before creating access points.
        </p>

        <.table id="access-points" rows={@access_points}>
          <:col :let={ap} label="Name">{ap.name}</:col>
          <:col :let={ap} label="Site">{ap.site.name}</:col>
          <:col :let={ap} label="GLN"><code class="text-xs">{ap.gln}</code></:col>
          <:action :let={ap}>
            <.link phx-click="edit" phx-value-id={ap.id}>Edit</.link>
          </:action>
          <:empty>No access points yet. Add your first one with the button above.</:empty>
        </.table>
      </div>
      <.modal :if={@show_form} id="access-point-modal" show on_cancel={JS.push("close_form")}>
        <.header>{if @editing, do: "Edit access point", else: "Add an access point"}</.header>

        <.form for={@form} id="access_point_form" phx-submit="save" phx-change="validate">
          <.input field={@form[:name]} type="text" label="Name" required />
          <.input
            field={@form[:site_id]}
            type="select"
            label="Site"
            prompt="Choose a site"
            options={Enum.map(@sites, &{&1.name, &1.id})}
            required
          />
          <div class="mt-4 flex gap-3">
            <.button phx-disable-with="Saving...">Save</.button>
            <.button type="button" variant="secondary" phx-click="close_form">Cancel</.button>
          </div>
        </.form>
      </.modal>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    sites = Access.list_sites(socket.assigns.current_scope)

    {:ok,
     socket
     |> assign(:sites, sites)
     |> assign(:editing, false)
     |> assign(:show_form, false)
     |> assign(:access_point, nil)
     |> assign_access_points()
     |> assign_form(Access.change_access_point(%AccessPoint{}))}
  end

  @impl true
  def handle_event("validate", %{"access_point" => params}, socket) do
    changeset =
      current_access_point(socket)
      |> Access.change_access_point(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"access_point" => params}, socket) do
    scope = socket.assigns.current_scope

    result =
      if socket.assigns.editing do
        Access.update_access_point(scope, socket.assigns.access_point, params)
      else
        Access.create_access_point(scope, params)
      end

    case result do
      {:ok, _access_point} ->
        {:noreply,
         socket
         |> put_flash(:info, "Access point saved.")
         |> close_form()
         |> assign_access_points()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("new", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing, false)
     |> assign(:show_form, true)
     |> assign(:access_point, nil)
     |> assign_form(Access.change_access_point(%AccessPoint{}))}
  end

  def handle_event("edit", %{"id" => id}, socket) do
    access_point = Access.get_access_point_for_scope!(socket.assigns.current_scope, id)

    {:noreply,
     socket
     |> assign(:editing, true)
     |> assign(:show_form, true)
     |> assign(:access_point, access_point)
     |> assign_form(Access.change_access_point(access_point))}
  end

  def handle_event("close_form", _params, socket), do: {:noreply, close_form(socket)}

  defp close_form(socket) do
    socket
    |> assign(:editing, false)
    |> assign(:show_form, false)
    |> assign(:access_point, nil)
    |> assign_form(Access.change_access_point(%AccessPoint{}))
  end

  defp current_access_point(socket), do: socket.assigns.access_point || %AccessPoint{}

  defp assign_access_points(socket),
    do: assign(socket, :access_points, Access.list_access_points(socket.assigns.current_scope))

  defp assign_form(socket, changeset),
    do: assign(socket, :form, to_form(changeset, as: "access_point"))
end
