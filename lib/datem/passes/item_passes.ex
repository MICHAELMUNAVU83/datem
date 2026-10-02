defmodule Datem.Passes.ItemPasses do

  import Ecto.Query, warn: false

  alias Datem.Repo
  alias Datem.Accounts.Scope
  alias Datem.Tenancy
  alias Datem.Organizations.Employee
  alias Datem.Accounts.UserNotifier
  alias Datem.Passes.{EmployeePass, ItemPass}

def list_item_passes(%Scope{} = scope) do
  ItemPass
  |> Tenancy.scope(scope)
  |> preload([:requested_by, :approver])
  |> order_by([p], desc: p.inserted_at)
  |> Repo.all()
end

def get_item_pass_for_scope!(%Scope{} = scope, id) do
  ItemPass |> Tenancy.scope(scope) |> preload([:requested_by, :approver]) |> Repo.get!(id)
end

@doc "Requests an item pass on behalf of `requested_by`. Routes to their head_employee for approval."
def request_item_pass(%Scope{} = scope, %Employee{} = requested_by, attrs) do
  requested_by = Repo.preload(requested_by, :head_employee)
  token = random_token()

  attrs =
    Map.merge(attrs, %{
      "requested_by_id" => requested_by.id,
      "approver_id" => requested_by.head_employee_id,
      "organization_id" => Tenancy.organization_id!(scope)
    })

  with {:ok, pass} <-
         %ItemPass{}
         |> ItemPass.changeset(attrs)
         |> Ecto.Changeset.put_change(:token, token)
         |> Repo.insert() do
    notify_item_pass_requested(pass, requested_by)
    {:ok, pass}
  end
end

@doc "Public, unauthenticated: looks up a pending item pass by its decision-link token."
def get_item_pass_by_token(token) when is_binary(token) do
  ItemPass
  |> where([p], p.token == ^token and p.status == "pending")
  |> preload([:requested_by, :approver, :organization])
  |> Repo.one()
end

@doc "Approves or denies a pending item pass, notifying the requester either way."
def decide_item_pass(%ItemPass{status: "pending"} = pass, decision)
    when decision in ["approved", "denied"] do
  with {:ok, pass} <- pass |> ItemPass.decision_changeset(decision) |> Repo.update() do
    notify_item_pass_decided(pass)
    {:ok, pass}
  end
end

@doc "Marks a returnable item pass as returned. Caller must be in the same organisation."
def mark_item_returned(%Scope{} = scope, %ItemPass{} = pass) do
  ensure_same_organization!(scope, pass)
  pass |> ItemPass.return_changeset() |> Repo.update()
end

defp notify_item_pass_requested(%ItemPass{} = pass, %Employee{head_employee: %Employee{email: email}})
     when is_binary(email) do
  pass = Repo.preload(pass, :requested_by)

  UserNotifier.deliver_item_pass_request(
    email,
    pass,
    pass_decision_url(:item, pass.token, "approve"),
    pass_decision_url(:item, pass.token, "deny")
  )
end

defp notify_item_pass_requested(_pass, _requested_by), do: :ok

defp notify_item_pass_decided(%ItemPass{} = pass) do
  pass = Repo.preload(pass, :requested_by)
  if pass.requested_by.email, do: UserNotifier.deliver_item_pass_decision(pass.requested_by.email, pass)
  :ok
end


  ## Shared

  defp pass_decision_url(:employee, token, action),
    do: DatemWeb.Endpoint.url() <> "/passes/employee/#{token}/#{action}"

  defp pass_decision_url(:item, token, action),
    do: DatemWeb.Endpoint.url() <> "/passes/item/#{token}/#{action}"

  defp ensure_same_organization!(%Scope{} = scope, resource) do
    if resource.organization_id != Tenancy.organization_id!(scope) do
      raise Ecto.NoResultsError, queryable: resource.__struct__
    end
  end

  defp random_token, do: 16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
end
