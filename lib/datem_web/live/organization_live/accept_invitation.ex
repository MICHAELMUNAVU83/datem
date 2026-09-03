defmodule DatemWeb.OrganizationLive.AcceptInvitation do
  use DatemWeb, :live_view

  alias Datem.Organizations

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm text-center">
        <.header :if={@invitation}>
          Join {@invitation.organization.name}
          <:subtitle>
            You've been invited as {@invitation.role}.
          </:subtitle>
        </.header>

        <div :if={@invitation}>
          <%= if @current_scope && @current_scope.user do %>
            <.button phx-click="accept" phx-disable-with="Joining...">
              Accept invitation
            </.button>
          <% else %>
            <p class="text-sm text-gray-600">
              Log in or create an account with <strong>{@invitation.email}</strong>
              to accept this invitation.
            </p>
            <div class="mt-4 flex justify-center gap-3">
              <.link navigate={~p"/users/log-in"} class="font-semibold text-blue-600 hover:underline">
                Log in
              </.link>
              <.link
                navigate={~p"/users/register"}
                class="font-semibold text-blue-600 hover:underline"
              >
                Register
              </.link>
            </div>
          <% end %>
        </div>

        <.header :if={!@invitation}>
          Invitation not found
          <:subtitle>This invitation link is invalid, expired, or has already been used.</:subtitle>
        </.header>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    invitation = Organizations.get_pending_invitation_by_token(token)
    {:ok, assign(socket, invitation: invitation, token: token)}
  end

  @impl true
  def handle_event("accept", _params, socket) do
    %{invitation: invitation, current_scope: scope} = socket.assigns

    case Organizations.accept_invitation(invitation, scope.user) do
      {:ok, %{organization: organization}} ->
        {:noreply,
         socket
         |> put_flash(:info, "Welcome to #{organization.name}!")
         |> redirect(to: ~p"/organizations/switch/#{organization.id}")}

      {:error, :email_mismatch} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "This invitation was sent to #{invitation.email}. Log in with that email to accept it."
         )}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "This invitation is no longer valid.")}
    end
  end
end
