defmodule DatemWeb.OrganizationLive.Members do
  use DatemWeb, :live_view

  on_mount {DatemWeb.UserAuth, {:require_role, [:owner, :admin]}}

  alias Datem.Organizations
  alias Datem.Organizations.Invitation

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Members
        <:subtitle>People with access to {@current_scope.organization.name}</:subtitle>
      </.header>

      <.table id="members" rows={@members}>
        <:col :let={membership} label="Email">{membership.user.email}</:col>
        <:col :let={membership} label="Role">
          <.badge>{membership.role}</.badge>
        </:col>
      </.table>

      <div class="divider" />

      <.header>
        Pending invitations
      </.header>

      <.table id="invitations" rows={@invitations}>
        <:col :let={invitation} label="Email">{invitation.email}</:col>
        <:col :let={invitation} label="Role">
          <.badge>{invitation.role}</.badge>
        </:col>
        <:action :let={invitation}>
          <.link
            phx-click="revoke"
            phx-value-id={invitation.id}
            data-confirm="Revoke this invitation?"
          >
            Revoke
          </.link>
        </:action>
        <:empty>No pending invitations.</:empty>
      </.table>

      <div class="divider" />

      <.header>Invite someone</.header>

      <.form for={@form} id="invite_form" phx-submit="invite" phx-change="validate">
        <.input field={@form[:email]} type="email" label="Email" required />
        <.input
          field={@form[:role]}
          type="select"
          label="Role"
          options={Enum.map(Invitation.invitable_roles(), &{Phoenix.Naming.humanize(&1), &1})}
          required
        />
        <.button phx-disable-with="Sending invite...">Send invitation</.button>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign_members_and_invitations()
     |> assign(:form, to_form(Ecto.Changeset.change(%Invitation{}), as: "invitation"))}
  end

  @impl true
  def handle_event("validate", %{"invitation" => params}, socket) do
    changeset =
      %Invitation{}
      |> Ecto.Changeset.cast(params, [:email, :role])
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: "invitation"))}
  end

  def handle_event("invite", %{"invitation" => params}, socket) do
    scope = socket.assigns.current_scope

    result =
      Organizations.invite_member(scope, &url(~p"/invitations/#{&1}"), params)

    case result do
      {:ok, _invitation} ->
        {:noreply,
         socket
         |> put_flash(:info, "Invitation sent.")
         |> assign_members_and_invitations()
         |> assign(:form, to_form(Ecto.Changeset.change(%Invitation{}), as: "invitation"))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: "invitation"))}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You are not authorized to invite members.")}
    end
  end

  def handle_event("revoke", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    invitation = Enum.find(socket.assigns.invitations, &(&1.id == String.to_integer(id)))

    case invitation && Organizations.revoke_invitation(scope, invitation) do
      {:ok, _} ->
        {:noreply,
         socket |> put_flash(:info, "Invitation revoked.") |> assign_members_and_invitations()}

      _ ->
        {:noreply, put_flash(socket, :error, "Couldn't revoke that invitation.")}
    end
  end

  defp assign_members_and_invitations(socket) do
    scope = socket.assigns.current_scope

    socket
    |> assign(:members, Organizations.list_members(scope))
    |> assign(:invitations, Organizations.list_pending_invitations(scope))
  end
end
