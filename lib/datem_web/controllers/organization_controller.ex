defmodule DatemWeb.OrganizationController do
  use DatemWeb, :controller

  alias Datem.Organizations

  @doc """
  Switches the caller's active organisation. Verifies membership before
  writing to the session, so a user can never switch into an organisation
  they don't belong to.
  """
  def switch(conn, %{"organization_id" => organization_id}) do
    user = conn.assigns.current_scope.user

    membership = Organizations.resolve_current_membership(user, organization_id)

    if membership && to_string(membership.organization_id) == to_string(organization_id) do
      conn
      |> put_session(:current_organization_id, membership.organization_id)
      |> redirect(to: ~p"/")
    else
      conn
      |> put_flash(:error, "You don't have access to that organisation.")
      |> redirect(to: ~p"/")
    end
  end
end
