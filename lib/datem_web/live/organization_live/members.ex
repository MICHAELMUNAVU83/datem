defmodule DatemWeb.OrganizationLive.Members do
  use DatemWeb, :live_view

  on_mount {DatemWeb.UserAuth, {:require_role, [:owner, :admin]}}

  alias Datem.Organizations
  alias Datem.Organizations.Invitation

  @impl true
  def render(assigns) do
    ~H"""

    <Layouts.app flash={@flash} current_scope={@current_scope} max_width="max-w-full">
      <div class="mb-6 overflow-hidden rounded-xl border border-blue-100">
        <.pass_header
          icon="hero-users"
          title="Members"
          subtitle={"People with access to #{@current_scope.organization.name}"}
        >
          <.button phx-click="new">Invite someone</.button>
        </.pass_header>

        <.table id="members" rows={@members}>
          <:col :let={membership} label="Email">{membership.user.email}</:col>
          <:col :let={membership} label="Role">
            <.badge>{membership.role}</.badge>
          </:col>
        </.table>
      </div>

      <div class="mb-6 overflow-hidden rounded-xl border border-gray-200">
        <div class="bg-gray-50 px-6 py-4">
          <p class="text-lg font-semibold text-gray-900">Pending invitations</p>
        </div>

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
      </div>

      <.modal :if={@show_form} id="invite-modal" show on_cancel={JS.push("close_form")}>
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
          <div class="mt-4 flex gap-3">
            <.button phx-disable-with="Sending invite...">Send invitation</.button>
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
     |> assign_members_and_invitations()
     |> assign(:show_form, false)
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
         |> assign(:show_form, false)
         |> assign_members_and_invitations()
         |> assign(:form, to_form(Ecto.Changeset.change(%Invitation{}), as: "invitation"))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: "invitation"))}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You are not authorized to invite members.")}
    end
  end

  def handle_event("new", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_form, true)
     |> assign(:form, to_form(Ecto.Changeset.change(%Invitation{}), as: "invitation"))}
  end

  def handle_event("close_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_form, false)
     |> assign(:form, to_form(Ecto.Changeset.change(%Invitation{}), as: "invitation"))}
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
