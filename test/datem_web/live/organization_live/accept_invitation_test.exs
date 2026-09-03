defmodule DatemWeb.OrganizationLive.AcceptInvitationTest do
  use DatemWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Datem.AccountsFixtures
  import Datem.OrganizationsFixtures

  alias Datem.Organizations

  test "shows an invalid message for an unknown token", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/invitations/not-a-real-token")
    assert html =~ "Invitation not found"
  end

  test "prompts a logged-out visitor to log in or register", %{conn: conn} do
    %{user: owner, organization: organization} = user_with_org_fixture()
    scope = scope_fixture(owner, organization)
    {invitation, token} = invitation_fixture(scope)

    {:ok, _lv, html} = live(conn, ~p"/invitations/#{token}")

    assert html =~ organization.name
    assert html =~ invitation.email
    assert html =~ "Log in"
    assert html =~ "Register"
  end

  test "lets a logged-in matching user accept", %{conn: conn} do
    %{user: owner, organization: organization} = user_with_org_fixture()
    scope = scope_fixture(owner, organization)

    invitee = user_fixture()

    {_invitation, token} =
      invitation_fixture(scope, %{"email" => invitee.email, "role" => "operator"})

    {:ok, lv, _html} = conn |> log_in_user(invitee) |> live(~p"/invitations/#{token}")

    {:error, {:redirect, %{to: to}}} =
      lv
      |> element("button", "Accept invitation")
      |> render_click()

    assert to == ~p"/organizations/switch/#{organization.id}"

    membership = Organizations.get_membership(invitee, organization)
    assert membership.role == :operator
  end

  test "refuses to accept for a mismatched email", %{conn: conn} do
    %{user: owner, organization: organization} = user_with_org_fixture()
    scope = scope_fixture(owner, organization)

    {_invitation, token} =
      invitation_fixture(scope, %{"email" => unique_user_email(), "role" => "viewer"})

    someone_else = user_fixture()

    {:ok, lv, _html} = conn |> log_in_user(someone_else) |> live(~p"/invitations/#{token}")

    html =
      lv
      |> element("button", "Accept invitation")
      |> render_click()

    assert html =~ "Log in with that email"
    refute Organizations.get_membership(someone_else, organization)
  end
end
