defmodule DatemWeb.AccessLive.Sites do
  use DatemWeb, :live_view

  on_mount {DatemWeb.UserAuth, {:require_role, [:owner, :admin]}}

  alias Datem.Access
  alias Datem.Access.Site

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Sites
        <:subtitle>Physical locations, each identified by a GS1 GLN</:subtitle>
      </.header>

      <.table id="sites" rows={@sites}>
        <:col :let={site} label="Name">{site.name}</:col>
        <:col :let={site} label="Address">{site.address}</:col>
        <:col :let={site} label="GLN"><code class="text-xs">{site.gln}</code></:col>
        <:action :let={site}>
          <.link phx-click="edit" phx-value-id={site.id}>Edit</.link>
        </:action>
        <:empty>No sites yet. Add your first one below.</:empty>
      </.table>

      <div class="divider" />

      <.header>{if @editing, do: "Edit site", else: "Add a site"}</.header>

      <.form for={@form} id="site_form" phx-submit="save" phx-change="validate">
        <.input field={@form[:name]} type="text" label="Name" required />
        <.input field={@form[:address]} type="text" label="Address" />
        <.input field={@form[:capacity]} type="number" label="Capacity (for alerts, optional)" />
        <div class="mt-4 flex gap-3">
          <.button phx-disable-with="Saving...">Save</.button>
          <.button :if={@editing} type="button" phx-click="cancel_edit">Cancel</.button>
        </div>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:editing, false)
     |> assign(:site, nil)
     |> assign_sites()
     |> assign_form(Access.change_site(%Site{}))}
  end

  @impl true
  def handle_event("validate", %{"site" => params}, socket) do
    {:noreply,
     assign_form(
       socket,
       Access.change_site(current_site(socket), params) |> Map.put(:action, :validate)
     )}
  end

  def handle_event("save", %{"site" => params}, socket) do
    scope = socket.assigns.current_scope

    result =
      if socket.assigns.editing do
        Access.update_site(scope, socket.assigns.site, params)
      else
        Access.create_site(scope, params)
      end

    case result do
      {:ok, _site} ->
        {:noreply,
         socket
         |> put_flash(:info, "Site saved.")
         |> assign(:editing, false)
         |> assign(:site, nil)
         |> assign_sites()
         |> assign_form(Access.change_site(%Site{}))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    site = Access.get_site_for_scope!(socket.assigns.current_scope, id)

    {:noreply,
     socket
     |> assign(:editing, true)
     |> assign(:site, site)
     |> assign_form(Access.change_site(site))}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing, false)
     |> assign(:site, nil)
     |> assign_form(Access.change_site(%Site{}))}
  end

  defp current_site(socket), do: socket.assigns.site || %Site{}

  defp assign_sites(socket),
    do: assign(socket, :sites, Access.list_sites(socket.assigns.current_scope))

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset, as: "site"))
end
