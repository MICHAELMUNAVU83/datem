defmodule Datem.OrganizationsTest do
  use Datem.DataCase, async: true

  alias Datem.Organizations
  alias Datem.Organizations.Membership
  alias Datem.Tenancy

  import Datem.AccountsFixtures
  import Datem.OrganizationsFixtures

  describe "create_organization_with_owner/2" do
    test "creates an organisation and makes the user its owner" do
      user = user_fixture()

      assert {:ok, %{organization: organization, membership: membership}} =
               Organizations.create_organization_with_owner(user, "Acme Inc.")

      assert organization.name == "Acme Inc."
      assert organization.slug == "acme-inc"
      assert membership.role == :owner
      assert membership.user_id == user.id
      assert membership.organization_id == organization.id
    end

    test "generates a unique slug when the name collides" do
      user_a = user_fixture()
      user_b = user_fixture()

      {:ok, %{organization: org_a}} =
        Organizations.create_organization_with_owner(user_a, "Acme Inc.")

      {:ok, %{organization: org_b}} =
        Organizations.create_organization_with_owner(user_b, "Acme Inc.")

      assert org_a.slug != org_b.slug
    end

    test "rolls back the organisation if the owner membership can't be created" do
      fake_user = %Datem.Accounts.User{id: 999_999_999}

      assert {:error, %Ecto.Changeset{}} =
               Organizations.create_organization_with_owner(fake_user, "Ghost Inc.")

      assert Repo.aggregate(Organizations.Organization, :count) == 0
    end
  end

  describe "resolve_current_membership/2" do
    test "returns the membership matching the given organization_id" do
      user = user_fixture()
      {:ok, %{organization: org_a}} = Organizations.create_organization_with_owner(user, "Org A")
      {:ok, %{organization: org_b}} = Organizations.create_organization_with_owner(user, "Org B")

      membership = Organizations.resolve_current_membership(user, org_b.id)
      assert membership.organization_id == org_b.id

      membership = Organizations.resolve_current_membership(user, to_string(org_a.id))
      assert membership.organization_id == org_a.id
    end

    test "falls back to the oldest membership when organization_id is nil or unknown" do
      user = user_fixture()
      {:ok, %{organization: org_a}} = Organizations.create_organization_with_owner(user, "Org A")
      {:ok, %{organization: _org_b}} = Organizations.create_organization_with_owner(user, "Org B")

      assert Organizations.resolve_current_membership(user, nil).organization_id == org_a.id
      assert Organizations.resolve_current_membership(user, -1).organization_id == org_a.id
    end

    test "returns nil when the user has no memberships" do
      user = user_fixture()
      assert Organizations.resolve_current_membership(user, nil) == nil
    end
  end

  describe "tenant isolation" do
    setup do
      %{user: user_a, organization: org_a} = user_with_org_fixture()
      %{user: user_b, organization: org_b} = user_with_org_fixture()

      scope_a = scope_fixture(user_a, org_a)
      scope_b = scope_fixture(user_b, org_b)

      %{
        scope_a: scope_a,
        scope_b: scope_b,
        org_a: org_a,
        org_b: org_b,
        user_a: user_a,
        user_b: user_b
      }
    end

    test "list_members/1 never returns another organisation's members", %{
      scope_a: scope_a,
      scope_b: scope_b,
      user_a: user_a,
      user_b: user_b
    } do
      assert [%Membership{user_id: ^user_a.id}] = Organizations.list_members(scope_a)
      assert [%Membership{user_id: ^user_b.id}] = Organizations.list_members(scope_b)
    end

    test "get_organization_for_scope!/2 rejects another organisation's id", %{
      scope_a: scope_a,
      org_b: org_b
    } do
      assert_raise Ecto.NoResultsError, fn ->
        Organizations.get_organization_for_scope!(scope_a, org_b.id)
      end
    end

    test "add_member/3 cannot add a member to another organisation", %{
      scope_a: scope_a,
      org_b: org_b
    } do
      other_user = user_fixture()

      {:ok, membership} = Organizations.add_member(scope_a, other_user, :viewer)
      assert membership.organization_id == scope_a.organization.id
      refute membership.organization_id == org_b.id
    end

    test "add_member/3 is denied for a non-owner/admin scope", %{
      scope_a: scope_a,
      user_a: user_a,
      org_a: org_a
    } do
      viewer = user_fixture()
      {:ok, _} = Organizations.add_member(scope_a, viewer, :viewer)
      viewer_scope = scope_fixture(viewer, org_a)

      assert {:error, :unauthorized} = Organizations.add_member(viewer_scope, user_a, :admin)
    end

    test "list_pending_invitations/1 is scoped to the caller's organisation", %{
      scope_a: scope_a,
      scope_b: scope_b
    } do
      {invitation, _token} = invitation_fixture(scope_a)

      assert [found] = Organizations.list_pending_invitations(scope_a)
      assert found.id == invitation.id
      assert Organizations.list_pending_invitations(scope_b) == []
    end

    test "revoke_invitation/2 cannot revoke another organisation's invitation", %{
      scope_a: scope_a,
      scope_b: scope_b
    } do
      {invitation, _token} = invitation_fixture(scope_b)

      assert_raise Ecto.NoResultsError, fn ->
        Organizations.revoke_invitation(scope_a, invitation)
      end
    end

    test "Tenancy.scope/2 raises when the scope has no organization loaded" do
      user = user_fixture()
      scope = Datem.Accounts.Scope.for_user(user)

      assert_raise Tenancy.MissingOrganizationError, fn ->
        Tenancy.scope(Membership, scope) |> Repo.all()
      end
    end
  end

  describe "invitations" do
    test "invite_member/3 delivers an email and accept_invitation/2 creates a membership" do
      %{user: owner, organization: organization} = user_with_org_fixture()
      scope = scope_fixture(owner, organization)

      invitee = user_fixture()

      {invitation, _token} =
        invitation_fixture(scope, %{"email" => invitee.email, "role" => "operator"})

      assert {:ok, %{membership: membership}} =
               Organizations.accept_invitation(invitation, invitee)

      assert membership.role == :operator
      assert membership.organization_id == organization.id
    end

    test "accept_invitation/2 rejects a mismatched email" do
      %{user: owner, organization: organization} = user_with_org_fixture()
      scope = scope_fixture(owner, organization)

      {invitation, _token} =
        invitation_fixture(scope, %{"email" => unique_user_email(), "role" => "viewer"})

      someone_else = user_fixture()

      assert {:error, :email_mismatch} = Organizations.accept_invitation(invitation, someone_else)
    end

    test "get_pending_invitation_by_token/1 returns nil for an unknown token" do
      assert Organizations.get_pending_invitation_by_token("not-a-real-token") == nil
    end

    test "get_pending_invitation_by_token/1 finds a pending invitation by its raw token" do
      %{user: owner, organization: organization} = user_with_org_fixture()
      scope = scope_fixture(owner, organization)

      {invitation, token} = invitation_fixture(scope)

      found = Organizations.get_pending_invitation_by_token(token)
      assert found.id == invitation.id
    end
  end

  describe "authorization" do
    test "has_role?/2 and role_at_least?/2 reflect the scope's membership" do
      %{user: owner, organization: organization} = user_with_org_fixture()
      owner_scope = scope_fixture(owner, organization)

      viewer = user_fixture()
      add_member_fixture(owner_scope, viewer, :viewer)
      viewer_scope = scope_fixture(viewer, organization)

      assert Organizations.has_role?(owner_scope, [:owner])
      refute Organizations.has_role?(viewer_scope, [:owner, :admin])
      assert Organizations.role_at_least?(owner_scope, :admin)
      refute Organizations.role_at_least?(viewer_scope, :operator)
    end
  end
end
