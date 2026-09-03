defmodule Datem.Tenancy do
  @moduledoc """
  Shared scoping layer that keeps tenant-owned queries from ever crossing
  organisation boundaries.

  Every context that touches tenant-owned data should build its base query
  and pass it through `scope/2` (or use `organization_id!/1` directly) rather
  than filtering by `organization_id` ad hoc. The current organisation always
  comes from `%Datem.Accounts.Scope{}`, which is resolved once per session
  from the caller's active membership — never from user-supplied params.
  """

  import Ecto.Query

  alias Datem.Accounts.Scope

  defmodule MissingOrganizationError do
    defexception message: "no organization loaded on the current scope"
  end

  @doc """
  Adds a `where organization_id == ^org_id` guard to the given queryable,
  using the organisation carried by `scope`.

  Raises `Datem.Tenancy.MissingOrganizationError` if the scope has no
  organisation loaded, so a context can never accidentally return
  unscoped, cross-tenant data.
  """
  def scope(queryable, %Scope{} = scope) do
    org_id = organization_id!(scope)
    from x in queryable, where: x.organization_id == ^org_id
  end

  @doc "Returns the id of the organisation carried by `scope`, raising if there isn't one."
  def organization_id!(%Scope{organization: %{id: id}}), do: id

  def organization_id!(%Scope{organization: nil}) do
    raise MissingOrganizationError
  end
end
