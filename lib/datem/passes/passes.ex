defmodule Datem.Passes do
  @moduledoc """
  Employee exit passes ("stepping out, needs a head's sign-off") and item
  passes (moving a company asset off-site, returnable or not). Both route
  through the subject's `head_employee_id` for approval and are approved
  or denied via an emailed token link — the same no-login pattern
  `Organizations.Invitation` and `Access.PreRegistration` already use, so a
  department head never needs a Datem account just to sign off a request.
  """

  import Ecto.Query, warn: false

  alias Datem.Repo
  alias Datem.Accounts.Scope
  alias Datem.Tenancy
  alias Datem.Organizations.Employee
  alias Datem.Accounts.UserNotifier
  alias Datem.Passes.{EmployeePass, ItemPass}

    alias Datem.Passes.CarPass
alias Datem.Access.Vehicle


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

def list_car_passes(%Scope{} = scope) do
  CarPass
  |> Tenancy.scope(scope)
  |> preload([:vehicle, :requested_by, :approver])
  |> order_by([p], desc: p.inserted_at)
  |> Repo.all()
end

def get_car_pass_for_scope!(%Scope{} = scope, id) do
  CarPass |> Tenancy.scope(scope) |> preload([:vehicle, :requested_by, :approver]) |> Repo.get!(id)
end

def request_car_pass(%Scope{} = scope, %Employee{} = requested_by, attrs) do
  requested_by = Repo.preload(requested_by, :head_employee)
  token = random_token()

  attrs =
    Map.merge(attrs, %{
      "requested_by_id" => requested_by.id,
      "approver_id" => requested_by.head_employee_id,
      "organization_id" => Tenancy.organization_id!(scope)
    })

  with {:ok, pass} <-
         %CarPass{}
         |> CarPass.changeset(attrs)
         |> Ecto.Changeset.put_change(:token, token)
         |> Repo.insert() do
    notify_car_pass_requested(pass, requested_by)
    {:ok, pass}
  end
end

def get_car_pass_by_token(token) when is_binary(token) do
  CarPass
  |> where([p], p.token == ^token and p.status == "pending")
  |> preload([:vehicle, :requested_by, :approver, :organization])
  |> Repo.one()
end

def decide_car_pass(%CarPass{status: "pending"} = pass, decision, reason \\ nil)
    when decision in ["approved", "denied"] do
  with {:ok, pass} <- pass |> CarPass.decision_changeset(decision, reason) |> Repo.update() do
    notify_car_pass_decided(pass)
    {:ok, pass}
  end
end

@doc "Records the vehicle leaving: caller must be in the same organisation, pass must be approved."
def record_car_departure(%Scope{} = scope, %CarPass{status: "approved"} = pass, mileage_out) do
  ensure_same_organization!(scope, pass)
  pass |> CarPass.depart_changeset(mileage_out) |> Repo.update()
end

@doc "Records the vehicle's return."
def record_car_return(%Scope{} = scope, %CarPass{status: "out"} = pass, mileage_in) do
  ensure_same_organization!(scope, pass)
  pass |> CarPass.return_changeset(mileage_in) |> Repo.update()
end

defp notify_car_pass_requested(%CarPass{} = pass, %Employee{head_employee: %Employee{email: email}})
     when is_binary(email) do
  pass = Repo.preload(pass, [:requested_by, :vehicle])
  UserNotifier.deliver_car_pass_request(email, pass, pass_decision_url(:car, pass.token))
end

defp notify_car_pass_requested(_pass, _requested_by), do: :ok

defp notify_car_pass_decided(%CarPass{} = pass) do
  pass = Repo.preload(pass, :requested_by)
  if pass.requested_by.email, do: UserNotifier.deliver_car_pass_decision(pass.requested_by.email, pass)
  :ok
end

  ## Employee passes

  def list_employee_passes(%Scope{} = scope) do
    EmployeePass
    |> Tenancy.scope(scope)
    |> preload([:employee, :requested_by, :approver])
    |> order_by([p], desc: p.inserted_at)
    |> Repo.all()
  end

  @doc "Requests an exit pass for `employee` (self or on someone's behalf). Routes to the employee's head_employee for approval."
  def request_employee_pass(%Scope{} = scope, %Employee{} = employee, %Employee{} = requested_by, attrs) do
    employee = Repo.preload(employee, :head_employee)
    token = random_token()

    attrs =
      Map.merge(attrs, %{
        "employee_id" => employee.id,
        "requested_by_id" => requested_by.id,
        "approver_id" => employee.head_employee_id,
        "organization_id" => Tenancy.organization_id!(scope)
      })

    with {:ok, pass} <-
           %EmployeePass{}
           |> EmployeePass.changeset(attrs)
           |> Ecto.Changeset.put_change(:token, token)
           |> Repo.insert() do
      notify_employee_pass_requested(pass, employee)
      {:ok, pass}
    end
  end

  def get_employee_pass_by_token(token) when is_binary(token) do
    EmployeePass
    |> where([p], p.token == ^token and p.status == "pending")
    |> preload([:employee, :requested_by, :approver, :organization])
    |> Repo.one()
  end

  def decide_employee_pass(%EmployeePass{status: "pending"} = pass, decision)
      when decision in ["approved", "denied"] do
    with {:ok, pass} <- pass |> EmployeePass.decision_changeset(decision) |> Repo.update() do
      notify_employee_pass_decided(pass)
      {:ok, pass}
    end
  end


  def decide_employee_pass(%EmployeePass{status: "pending"} = pass, decision, reason \\ nil)
    when decision in ["approved", "denied"] do
  with {:ok, pass} <- pass |> EmployeePass.decision_changeset(decision, reason) |> Repo.update() do
    notify_employee_pass_decided(pass)
    {:ok, pass}
  end
end

  defp notify_employee_pass_requested(%EmployeePass{} = pass, %Employee{head_employee: %Employee{email: email}} = _employee)
       when is_binary(email) do
    pass = Repo.preload(pass, [:employee, :requested_by])

    UserNotifier.deliver_employee_pass_request(
      email,
      pass,
      pass_decision_url(:employee, pass.token, "approve"),
      pass_decision_url(:employee, pass.token, "deny")
    )
  end

  defp notify_employee_pass_requested(_pass, _employee), do: :ok

  defp notify_employee_pass_decided(%EmployeePass{} = pass) do
    pass = Repo.preload(pass, [:employee, :requested_by])
    recipient = pass.requested_by

    if recipient.email, do: UserNotifier.deliver_employee_pass_decision(recipient.email, pass)
    :ok
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



  defp pass_decision_url(:employee, token, action),
    do: DatemWeb.Endpoint.url() <> "/passes/employee/#{token}/#{action}"

  defp pass_decision_url(:item, token, action),
    do: DatemWeb.Endpoint.url() <> "/passes/item/#{token}/#{action}"

  defp ensure_same_organization!(%Scope{} = scope, resource) do
    if resource.organization_id != Tenancy.organization_id!(scope) do
      raise Ecto.NoResultsError, queryable: resource.__struct__
    end
  end

  defp pass_decision_url(:employee, token), do: DatemWeb.Endpoint.url() <> "/passes/employee/#{token}"
defp pass_decision_url(:item, token), do: DatemWeb.Endpoint.url() <> "/passes/item/#{token}"
defp pass_decision_url(:car, token), do: DatemWeb.Endpoint.url() <> "/passes/car/#{token}"

  defp random_token, do: 16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
end
