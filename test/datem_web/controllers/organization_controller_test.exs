defmodule DatemWeb.OrganizationControllerTest do
  use DatemWeb.ConnCase, async: true

  import Datem.AccountsFixtures
  import Datem.OrganizationsFixtures

  describe "switch/2" do
    test "switches the session's active organisation when the user is a member", %{conn: conn} do
      user = user_fixture()
      %{organization: _org_a} = user_with_org_fixture(%{user: user, organization_name: "Org A"})
      %{organization: org_b} = user_with_org_fixture(%{user: user, organization_name: "Org B"})

      conn =
        conn
        |> log_in_user(user)
        |> get(~p"/organizations/switch/#{org_b.id}")

      assert redirected_to(conn) == ~p"/"
      assert get_session(conn, :current_organization_id) == org_b.id
    end

    test "refuses to switch into an organisation the user doesn't belong to", %{conn: conn} do
      user = user_fixture()
      %{organization: own_org} = user_with_org_fixture(%{user: user})
      %{organization: other_org} = user_with_org_fixture()

      conn =
        conn
        |> log_in_user(user)
        |> get(~p"/organizations/switch/#{other_org.id}")

      assert redirected_to(conn) == ~p"/"
      assert get_session(conn, :current_organization_id) in [nil, own_org.id]
      refute get_session(conn, :current_organization_id) == other_org.id
    end
  end
end
