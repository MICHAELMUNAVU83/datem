defmodule DatemWeb.OrganizationLive.MembersTest do
  use DatemWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Datem.AccountsFixtures
  import Datem.OrganizationsFixtures

  alias Datem.Organizations

  describe "access control" do
    test "owners can view the members page", %{conn: conn} do
      user = user_fixture()
      user_with_org_fixture(%{user: user})

      {:ok, _lv, html} = conn |> log_in_user(user) |> live(~p"/organization/members")

      assert html =~ "Members"
    end

    test "viewers are redirected away", %{conn: conn} do
      %{user: owner, organization: organization} = user_with_org_fixture()
      owner_scope = scope_fixture(owner, organization)

      viewer = user_fixture()
      add_member_fixture(owner_scope, viewer, :viewer)

      assert {:error, {:redirect, %{to: "/"}}} =
               conn |> log_in_user(viewer) |> live(~p"/organization/members")
    end

    test "users with no organisation are redirected away", %{conn: conn} do
      user = user_fixture()

      assert {:error, {:redirect, %{to: "/"}}} =
               conn |> log_in_user(user) |> live(~p"/organization/members")
    end
  end

  describe "inviting and revoking" do
    test "sends an invitation", %{conn: conn} do
      %{user: owner, organization: organization} = user_with_org_fixture()
      scope = scope_fixture(owner, organization)

      {:ok, lv, _html} = conn |> log_in_user(owner) |> live(~p"/organization/members")

      email = unique_user_email()

      html =
        lv
        |> form("#invite_form", invitation: %{"email" => email, "role" => "operator"})
        |> render_submit()

      assert html =~ "Invitation sent."
      assert html =~ email

      assert [invitation] = Organizations.list_pending_invitations(scope)
      assert invitation.email == email
      assert invitation.role == :operator
    end

    test "revokes a pending invitation", %{conn: conn} do
      %{user: owner, organization: organization} = user_with_org_fixture()
      scope = scope_fixture(owner, organization)
      {invitation, _token} = invitation_fixture(scope)

      {:ok, lv, html} = conn |> log_in_user(owner) |> live(~p"/organization/members")
      assert html =~ invitation.email

      html =
        lv
        |> element("#invitations a", "Revoke")
        |> render_click()

      refute html =~ invitation.email
      assert Organizations.list_pending_invitations(scope) == []
    end
  end
end
