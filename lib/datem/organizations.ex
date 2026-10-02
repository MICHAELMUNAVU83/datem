defmodule Datem.Organizations do
  @moduledoc """
  The Organizations context.

  Owns organisations, memberships (a user's role within an organisation),
  and invitations. This is also where role authorization checks live, since
  a role only ever makes sense in the context of a membership.
  """

  import Ecto.Query, warn: false

  alias Datem.Repo
  alias Datem.Accounts.{Scope, User}
  alias Datem.Organizations.{Organization, Membership, Invitation, InvitationNotifier, Employee}
  alias Datem.Tenancy


  @role_rank %{owner: 4, admin: 3, operator: 2, viewer: 1}

  ## Organizations

  @doc """
  Creates an organisation named `name` and makes `user` its owner, in a
  single transaction. Used at registration time, and the only way an
  organisation should ever be created.
  """
  def create_organization_with_owner(%User{} = user, name) when is_binary(name) do
    Repo.transact(fn ->
      with {:ok, organization} <- insert_organization_with_unique_slug(%{name: name}),
           {:ok, membership} <- do_add_member(organization, user, :owner) do
        {:ok, %{organization: organization, membership: membership}}
      end
    end)
  end

  @doc """
  Fetches the organisation identified by `id`, scoped to the caller's
  current organisation. Raises if `id` doesn't match the organisation
  already loaded on `scope` — this is what stops a stray parameter from
  ever reaching across tenants.
  """
  def get_organization_for_scope!(%Scope{} = scope, id) do
    org_id = Tenancy.organization_id!(scope)

    if to_string(org_id) == to_string(id) do
      Repo.get!(Organization, org_id)
    else
      raise Ecto.NoResultsError, queryable: Organization
    end
  end

  def change_organization(%Organization{} = organization, attrs \\ %{}) do
    Organization.settings_changeset(organization, attrs)
  end

  @doc "Updates the current organisation's settings. Caller must be owner or admin."
  def update_organization(%Scope{} = scope, attrs) do
    with :ok <- authorize(scope, [:owner, :admin]) do
      scope.organization
      |> Organization.settings_changeset(attrs)
      |> Repo.update()
    end
  end

  ## Memberships

  def get_membership(%User{} = user, %Organization{} = organization) do
    Repo.get_by(Membership, user_id: user.id, organization_id: organization.id)
  end

  @doc "All memberships (with their organisation preloaded) for a user, oldest first."
  def list_memberships_for_user(%User{} = user) do
    Membership
    |> where([m], m.user_id == ^user.id)
    |> order_by([m], asc: m.inserted_at)
    |> preload(:organization)
    |> Repo.all()
  end

  @doc "Members of the caller's current organisation."
  def list_members(%Scope{} = scope) do
    Membership
    |> Tenancy.scope(scope)
    |> preload(:user)
    |> order_by([m], asc: m.inserted_at)
    |> Repo.all()
  end

  @doc """
  Resolves which membership should be active for a user's session: the
  membership matching `organization_id` if the user belongs to it, or the
  user's oldest membership otherwise. Returns nil if the user has no
  memberships at all.

  `organization_id` is expected to come from the session, never from a
  request param, so a user can't switch into an organisation they aren't a
  member of just by editing a URL.
  """
  def resolve_current_membership(%User{} = user, organization_id) do
    memberships = list_memberships_for_user(user)

    Enum.find(memberships, List.first(memberships), fn m ->
      organization_id && to_string(m.organization_id) == to_string(organization_id)
    end)
  end

  @doc "Adds `user` to `organization` with `role`. Caller must be owner or admin."
  def add_member(%Scope{} = scope, %User{} = user, role) do
    with :ok <- authorize(scope, [:owner, :admin]) do
      do_add_member(scope.organization, user, role)
    end
  end

  defp do_add_member(%Organization{} = organization, %User{} = user, role) do
    %Membership{}
    |> Membership.changeset(%{role: role, user_id: user.id, organization_id: organization.id})
    |> Repo.insert()
  end

  ## Roles / authorization

  @doc "Returns true if the scope's membership role is one of `roles`."
  def has_role?(%Scope{membership: %Membership{role: role}}, roles) when is_list(roles) do
    role in roles
  end

  def has_role?(%Scope{membership: nil}, _roles), do: false
  def has_role?(nil, _roles), do: false

  @doc "Returns true if the scope's membership role outranks or matches `role`."
  def role_at_least?(%Scope{membership: %Membership{role: role}}, min_role) do
    Map.fetch!(@role_rank, role) >= Map.fetch!(@role_rank, min_role)
  end

  def role_at_least?(%Scope{membership: nil}, _min_role), do: false
  def role_at_least?(nil, _min_role), do: false

  @doc "Returns `:ok` if the scope's role is one of `roles`, `{:error, :unauthorized}` otherwise."
  def authorize(%Scope{} = scope, roles) when is_list(roles) do
    if has_role?(scope, roles), do: :ok, else: {:error, :unauthorized}
  end

  ## Invitations

  @doc "Invites someone to the caller's current organisation. Caller must be owner or admin."
  def invite_member(%Scope{} = scope, invite_url_fun, attrs)
      when is_function(invite_url_fun, 1) do
    with :ok <- authorize(scope, [:owner, :admin]) do
      {raw_token, changeset} = Invitation.build(scope.organization, scope.user, attrs)

      case Repo.insert(changeset) do
        {:ok, invitation} ->
          InvitationNotifier.deliver_invitation(
            invitation,
            scope.organization,
            invite_url_fun.(raw_token)
          )

          {:ok, invitation}

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  @doc "Pending invitations for the caller's current organisation."
  def list_pending_invitations(%Scope{} = scope) do
    Invitation
    |> Tenancy.scope(scope)
    |> where([i], i.status == :pending)
    |> order_by([i], desc: i.inserted_at)
    |> Repo.all()
  end

  @doc "Revokes a pending invitation. Caller must be owner or admin."
  def revoke_invitation(%Scope{} = scope, %Invitation{} = invitation) do
    with :ok <- authorize(scope, [:owner, :admin]) do
      ensure_same_organization!(scope, invitation)

      invitation
      |> Invitation.revoke_changeset()
      |> Repo.update()
    end
  end

  defp ensure_same_organization!(%Scope{} = scope, %Invitation{} = invitation) do
    if invitation.organization_id != Tenancy.organization_id!(scope) do
      raise Ecto.NoResultsError, queryable: Invitation
    end
  end

  @doc """
  Looks up a pending, unexpired invitation by its raw token (as delivered
  in the invite email). Returns nil if the token is invalid, unknown,
  expired, or already used.
  """
  def get_pending_invitation_by_token(token) when is_binary(token) do
    with {:ok, decoded} <- Base.url_decode64(token, padding: false) do
      hash = :crypto.hash(:sha256, decoded)

      Invitation
      |> where([i], i.token_hash == ^hash and i.status == :pending)
      |> preload(:organization)
      |> Repo.one()
      |> reject_if_expired()
    else
      :error -> nil
    end
  end

  defp reject_if_expired(nil), do: nil

  defp reject_if_expired(%Invitation{} = invitation),
    do: if(Invitation.expired?(invitation), do: nil, else: invitation)

  @doc """
  Accepts an invitation on behalf of `user`, creating their membership.

  The invitation's email must match the user's email — this is what stops
  a token meant for one address being redeemed by a different account.
  """
  def accept_invitation(%Invitation{} = invitation, %User{} = user) do
    cond do
      invitation.status != :pending ->
        {:error, :not_pending}

      Invitation.expired?(invitation) ->
        {:error, :expired}

      String.downcase(invitation.email) != String.downcase(user.email) ->
        {:error, :email_mismatch}

      true ->
        Repo.transact(fn ->
          organization = Repo.get!(Organization, invitation.organization_id)

          with {:ok, membership} <- do_add_member(organization, user, invitation.role),
               {:ok, invitation} <- Repo.update(Invitation.accept_changeset(invitation)) do
            {:ok, %{membership: membership, invitation: invitation, organization: organization}}
          end
        end)
    end
  end



def list_employees(%Scope{} = scope) do
  Employee |> Tenancy.scope(scope) |> order_by([e], asc: e.name) |> Repo.all()
end

def get_employee_for_scope!(%Scope{} = scope, id) do
  Employee |> Tenancy.scope(scope) |> Repo.get!(id)
end

def change_employee(%Employee{} = employee, attrs \\ %{}), do: Employee.changeset(employee, attrs)

@doc "Adds a staff member to the caller's organisation. Caller must be owner or admin."
def create_employee(%Scope{} = scope, attrs) do
  with :ok <- authorize(scope, [:owner, :admin]) do
    %Employee{}
    |> Employee.changeset(Map.put(attrs, "organization_id", Tenancy.organization_id!(scope)))
    |> Repo.insert()
  end
end

def update_employee(%Scope{} = scope, %Employee{} = employee, attrs) do
  with :ok <- authorize(scope, [:owner, :admin]) do
    ensure_same_organization!(scope, employee)
    employee |> Employee.changeset(attrs) |> Repo.update()
  end
end

def delete_employee(%Scope{} = scope, %Employee{} = employee) do
  with :ok <- authorize(scope, [:owner, :admin]) do
    ensure_same_organization!(scope, employee)
    Repo.delete(employee)
  end
end


  @spec list_registerable_organizations() :: any()
  @doc "Public, unauthenticated: organisations visitors can register to visit."
def list_registerable_organizations do
  Organization
  |> order_by([o], asc: o.name)
  |> Repo.all()
end

@doc "Public, unauthenticated: staff a visitor can select as their host, for a given organisation."
def list_employees_for_organization(organization_id) do
  Employee
  |> where([e], e.organization_id == ^organization_id)
  |> order_by([e], asc: e.name)
  |> Repo.all()
end



defp insert_organization_with_unique_slug(attrs, suffix \\ nil) do
  attrs = for {k, v} <- attrs, into: %{}, do: {to_string(k), v}

  base_slug = Map.get(attrs, "slug") || slug_from_name(Map.get(attrs, "name", ""))
  candidate_slug = if suffix, do: "#{base_slug}-#{suffix}", else: base_slug

  %Organization{}
  |> Organization.changeset(Map.put(attrs, "slug", candidate_slug))
  |> Repo.insert()
  |> case do
    {:error, changeset} ->
      if suffix == nil and Keyword.has_key?(changeset.errors, :slug) do
        insert_organization_with_unique_slug(attrs, random_suffix())
      else
        {:error, changeset}
      end

    ok ->
      ok
  end
end


  defp random_suffix do
    4
    |> :crypto.strong_rand_bytes()
    |> Base.encode16(case: :lower)
  end

  defp slug_from_name(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> case do
      "" -> "org"
      slug -> slug
    end
  end

  @doc "Platform-admin only: every organisation in the system, alphabetically."
def list_all_organizations do
  Organization
  |> order_by([o], asc: o.name)
  |> Repo.all()
end

@doc "Platform-admin only: sets which modules an organisation has access to."
def set_organization_modules(%Organization{} = organization, modules) when is_list(modules) do
  organization
  |> Organization.changeset(%{modules: modules})
  |> Repo.update()
end

@doc "Platform-admin only: creates a new organisation with no members yet."
def create_organization(attrs) do
  insert_organization_with_unique_slug(attrs)
end
def has_module?(%Scope{organization: %Organization{modules: modules}}, module) do
  to_string(module) in modules
end

def has_module?(nil, _module), do: false
end
