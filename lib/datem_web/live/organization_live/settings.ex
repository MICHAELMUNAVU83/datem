defmodule DatemWeb.OrganizationLive.Settings do
  use DatemWeb, :live_view

  on_mount {DatemWeb.UserAuth, {:require_role, [:owner, :admin]}}

  alias Datem.Organizations

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Organisation settings
        <:subtitle>General details and your GS1 Company Prefix</:subtitle>
      </.header>

      <.form for={@form} id="organization_form" phx-submit="save" phx-change="validate">
        <.input field={@form[:name]} type="text" label="Organisation name" required />

        <.input
          field={@form[:gs1_company_prefix]}
          type="text"
          label="GS1 Company Prefix"
          placeholder="e.g. 0614141"
        />

        <p class="text-sm text-gray-600">
          <%= if @current_scope.organization.gs1_company_prefix do %>
            Identifiers issued for this organisation are GS1-interoperable.
          <% else %>
            No GS1 Company Prefix on file. Identifiers will use a Datem-internal
            prefix and are <span class="font-medium">not GS1-interoperable</span>
            until a licensed prefix is added.
          <% end %>
        </p>

        <.button phx-disable-with="Saving...">Save</.button>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    organization = socket.assigns.current_scope.organization

    {:ok, assign(socket, :form, to_form(Organizations.change_organization(organization)))}
  end

  @impl true
  def handle_event("validate", %{"organization" => params}, socket) do
    changeset =
      socket.assigns.current_scope.organization
      |> Organizations.change_organization(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"organization" => params}, socket) do
    case Organizations.update_organization(socket.assigns.current_scope, params) do
      {:ok, organization} ->
        scope =
          Datem.Accounts.Scope.put_organization(
            socket.assigns.current_scope,
            organization,
            socket.assigns.current_scope.membership
          )

        {:noreply,
         socket
         |> assign(:current_scope, scope)
         |> assign(:form, to_form(Organizations.change_organization(organization)))
         |> put_flash(:info, "Organisation settings updated.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You are not authorized to update these settings.")}
    end
  end
end
