defmodule Datem.OrganizationsFixtures do
  @moduledoc """
  Test helpers for creating entities via the `Datem.Organizations` context.
  """

  alias Datem.Accounts.Scope
  alias Datem.Organizations

  def unique_org_name, do: "Org #{System.unique_integer([:positive])}"

  @doc "Creates a user, an organisation, and makes the user its owner."
  def user_with_org_fixture(attrs \\ %{}) do
    user = attrs[:user] || Datem.AccountsFixtures.user_fixture()
    name = attrs[:organization_name] || unique_org_name()

    {:ok, %{organization: organization, membership: membership}} =
      Organizations.create_organization_with_owner(user, name)

    %{user: user, organization: organization, membership: membership}
  end

  @doc "Returns a scope for `user` with their membership in `organization` attached."
  def scope_fixture(user, organization) do
    membership = Organizations.get_membership(user, organization)

    user
    |> Scope.for_user()
    |> Scope.put_organization(organization, membership)
  end

  @doc "Owner scope fixture: a fresh user + org + owner membership, wired into a `%Scope{}`."
  def owner_scope_fixture(attrs \\ %{}) do
    %{user: user, organization: organization} = user_with_org_fixture(attrs)
    scope_fixture(user, organization)
  end

  @doc "Adds `user` to `organization` with `role`, bypassing the invite flow."
  def add_member_fixture(scope, user, role) do
    {:ok, membership} = Organizations.add_member(scope, user, role)
    membership
  end

  @doc "Creates a pending invitation to `scope`'s organisation, returning `{invitation, raw_token}`."
  def invitation_fixture(scope, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        "email" => Datem.AccountsFixtures.unique_user_email(),
        "role" => "viewer"
      })

    test_pid = self()

    {:ok, invitation} =
      Organizations.invite_member(
        scope,
        fn token ->
          send(test_pid, {:invitation_token, token})
          "https://example.com/invitations/#{token}"
        end,
        attrs
      )

    receive do
      {:invitation_token, token} -> {invitation, token}
    end
  end
end
