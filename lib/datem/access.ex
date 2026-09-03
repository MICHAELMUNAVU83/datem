defmodule Datem.Access do
  @moduledoc """
  The Visitor Access Management context: sites, access points, visitors,
  visitor passes, vehicles, and the access log they generate.

  Identifier issuance (GLN/GSRN/GIAI) and QR rendering are delegated to
  `Datem.GS1` rather than reimplemented here.
  """

  import Ecto.Query, warn: false

  alias Datem.Repo
  alias Datem.Accounts.Scope
  alias Datem.GS1
  alias Datem.Tenancy
  alias Datem.Access.{Site, AccessPoint, Visitor, VisitorPass, Vehicle, AccessLog}

  @pass_validity_hours 24

  ## Sites

  def list_sites(%Scope{} = scope) do
    Site |> Tenancy.scope(scope) |> order_by([s], asc: s.name) |> Repo.all()
  end

  def get_site_for_scope!(%Scope{} = scope, id) do
    Site |> Tenancy.scope(scope) |> Repo.get!(id)
  end

  def change_site(%Site{} = site, attrs \\ %{}), do: Site.changeset(site, attrs)

  @doc "Creates a site and issues its GLN in a single transaction."
  def create_site(%Scope{} = scope, attrs) do
    Repo.transact(fn ->
      with {:ok, site} <-
             %Site{}
             |> Site.changeset(Map.put(attrs, "organization_id", Tenancy.organization_id!(scope)))
             |> Repo.insert(),
           {:ok, identifier} <- GS1.issue_identifier(scope, :gln, "site", site.id) do
        site |> Site.gln_changeset(identifier.value) |> Repo.update()
      end
    end)
  end

  def update_site(%Scope{} = scope, %Site{} = site, attrs) do
    ensure_same_organization!(scope, site)
    site |> Site.changeset(attrs) |> Repo.update()
  end

  ## Access points

  def list_access_points(%Scope{} = scope) do
    AccessPoint
    |> Tenancy.scope(scope)
    |> preload(:site)
    |> order_by([a], asc: a.name)
    |> Repo.all()
  end

  def get_access_point_for_scope!(%Scope{} = scope, id) do
    AccessPoint |> Tenancy.scope(scope) |> preload(:site) |> Repo.get!(id)
  end

  def change_access_point(%AccessPoint{} = access_point, attrs \\ %{}),
    do: AccessPoint.changeset(access_point, attrs)

  @doc "Creates an access point and issues its GLN extension."
  def create_access_point(%Scope{} = scope, attrs) do
    Repo.transact(fn ->
      with {:ok, access_point} <-
             %AccessPoint{}
             |> AccessPoint.changeset(
               Map.put(attrs, "organization_id", Tenancy.organization_id!(scope))
             )
             |> Repo.insert(),
           {:ok, identifier} <- GS1.issue_identifier(scope, :gln, "access_point", access_point.id) do
        access_point |> AccessPoint.gln_changeset(identifier.value) |> Repo.update()
      end
    end)
  end

  def update_access_point(%Scope{} = scope, %AccessPoint{} = access_point, attrs) do
    ensure_same_organization!(scope, access_point)
    access_point |> AccessPoint.changeset(attrs) |> Repo.update()
  end

  ## Visitors

  def list_visitors(%Scope{} = scope) do
    Visitor |> Tenancy.scope(scope) |> order_by([v], desc: v.inserted_at) |> Repo.all()
  end

  def get_visitor_for_scope!(%Scope{} = scope, id) do
    Visitor |> Tenancy.scope(scope) |> preload(:visitor_passes) |> Repo.get!(id)
  end

  def change_visitor(%Visitor{} = visitor, attrs \\ %{}), do: Visitor.changeset(visitor, attrs)

  @doc "Registers a walk-in visitor. Does not issue a pass — call `issue_pass/2` for that."
  def register_visitor(%Scope{} = scope, attrs) do
    %Visitor{}
    |> Visitor.changeset(Map.put(attrs, "organization_id", Tenancy.organization_id!(scope)))
    |> Repo.insert()
  end

  def store_visitor_photo(%Scope{} = scope, %Visitor{} = visitor, photo_path) do
    ensure_same_organization!(scope, visitor)
    visitor |> Visitor.photo_changeset(photo_path) |> Repo.update()
  end

  @doc """
  Issues a visitor pass: a GSRN identifier plus a validity window. The
  pass's Digital Link QR is rendered on demand from the identifier via
  `Datem.GS1.qr_svg/2`, not stored.
  """
  def issue_pass(%Scope{} = scope, %Visitor{} = visitor, attrs \\ %{}) do
    ensure_same_organization!(scope, visitor)

    now = DateTime.utc_now() |> DateTime.truncate(:second)
    default_valid_to = DateTime.add(now, @pass_validity_hours, :hour)

    Repo.transact(fn ->
      with {:ok, identifier} <- GS1.issue_identifier(scope, :gsrn, "visitor_pass", visitor.id),
           {:ok, pass} <-
             %VisitorPass{}
             |> VisitorPass.changeset(
               Map.merge(
                 %{
                   valid_from: now,
                   valid_to: default_valid_to,
                   organization_id: Tenancy.organization_id!(scope),
                   visitor_id: visitor.id,
                   gs1_identifier_id: identifier.id
                 },
                 attrs
               )
             )
             |> Repo.insert(),
           {:ok, visitor} <- visitor |> Visitor.status_changeset("registered") |> Repo.update() do
        {:ok, %{pass: %{pass | gs1_identifier: identifier}, visitor: visitor}}
      end
    end)
  end

  def revoke_pass(%Scope{} = scope, %VisitorPass{} = pass) do
    ensure_same_organization!(scope, pass)
    pass |> VisitorPass.revoke_changeset() |> Repo.update()
  end

  def get_active_pass_for_visitor(%Scope{} = scope, visitor_id) do
    VisitorPass
    |> Tenancy.scope(scope)
    |> where([p], p.visitor_id == ^visitor_id and p.status == "active")
    |> order_by([p], desc: p.inserted_at)
    |> preload(:gs1_identifier)
    |> limit(1)
    |> Repo.one()
  end

  ## Pre-registration

  @doc "Creates the pending visitor stub behind a shareable pre-registration link. The token lives on the returned visitor's `invite_token` field."
  def create_pre_registration(%Scope{} = scope, host) when is_binary(host) do
    token = random_token()

    attrs = %{
      "host" => host,
      "organization_id" => Tenancy.organization_id!(scope),
      "invite_token" => token
    }

    case %Visitor{} |> Visitor.pre_registration_changeset(attrs) |> Repo.insert() do
      {:ok, visitor} -> {:ok, visitor}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc "Looks up a pending pre-registration by its public token. Returns nil if unknown or already completed."
  def get_pending_pre_registration_by_token(token) when is_binary(token) do
    Visitor
    |> where([v], v.invite_token == ^token and v.status == "pending")
    |> preload(:organization)
    |> Repo.one()
  end

  @doc """
  Completes a pre-registration: the visitor fills in their own details and
  a pass is issued immediately, scoped to the organisation that created
  the invite (never the caller's own session, since this runs as a public,
  unauthenticated visitor).
  """
  def complete_pre_registration(%Visitor{status: "pending"} = visitor, attrs) do
    scope = %Scope{organization: visitor.organization}

    Repo.transact(fn ->
      with {:ok, visitor} <-
             visitor |> Visitor.self_registration_changeset(attrs) |> Repo.update(),
           {:ok, %{pass: pass}} <- issue_pass(scope, visitor) do
        {:ok, %{visitor: visitor, pass: pass}}
      end
    end)
  end

  ## Vehicles

  def list_vehicles(%Scope{} = scope) do
    Vehicle
    |> Tenancy.scope(scope)
    |> preload(:gs1_identifier)
    |> order_by([v], desc: v.inserted_at)
    |> Repo.all()
  end

  def get_vehicle_for_scope!(%Scope{} = scope, id) do
    Vehicle |> Tenancy.scope(scope) |> preload(:gs1_identifier) |> Repo.get!(id)
  end

  def change_vehicle(%Vehicle{} = vehicle, attrs \\ %{}), do: Vehicle.changeset(vehicle, attrs)

  @doc "Registers a vehicle and issues its GIAI windscreen-tag identifier."
  def register_vehicle(%Scope{} = scope, attrs) do
    Repo.transact(fn ->
      with {:ok, vehicle} <-
             %Vehicle{}
             |> Vehicle.changeset(
               Map.put(attrs, "organization_id", Tenancy.organization_id!(scope))
             )
             |> Repo.insert(),
           {:ok, identifier} <- GS1.issue_identifier(scope, :giai, "vehicle", vehicle.id) do
        vehicle
        |> Vehicle.gs1_identifier_changeset(identifier.id)
        |> Repo.update()
        |> case do
          {:ok, vehicle} -> {:ok, %{vehicle | gs1_identifier: identifier}}
          error -> error
        end
      end
    end)
  end

  ## Access logs

  @doc """
  Resolves a scanned GS1 Digital Link to the subject it names (a
  `%VisitorPass{}` or `%Vehicle{}`) and records a scan at `access_point`,
  automatically alternating direction (`in`/`out`) based on the subject's
  last recorded direction.

  Returns `{:ok, log, entity, direction}` on acceptance, where `entity` is
  the visitor or vehicle to display, or `{:error, reason, entity}` /
  `{:error, reason}` if the code can't be resolved at all.
  """
  def scan(%Scope{} = scope, %AccessPoint{} = access_point, digital_link, operator \\ nil) do
    with {:ok, subject, entity} <- resolve_scan_subject(scope, digital_link) do
      direction = next_direction(scope, subject)

      case record_scan(scope, access_point, subject, direction, operator) do
        {:ok, log} -> {:ok, log, entity, direction}
        {:error, reason} -> {:error, reason, entity}
      end
    end
  end

  @doc """
  Resolves a scanned GS1 Digital Link to the subject and entity it names,
  scoped to the caller's organisation. A code from another tenant, an
  unknown code, a visitor with no active pass, or a revoked vehicle all
  resolve to distinct error reasons so the scanning view can show a clear
  denial message.
  """
  def resolve_scan_subject(%Scope{} = scope, digital_link) when is_binary(digital_link) do
    with {:ok, identifier} <- GS1.resolve_digital_link(scope, digital_link) do
      resolve_subject(scope, identifier)
    end
  end

  defp resolve_subject(scope, %{subject_type: "visitor_pass", subject_id: visitor_id}) do
    visitor_id = String.to_integer(visitor_id)

    case Visitor |> Tenancy.scope(scope) |> Repo.get(visitor_id) do
      nil ->
        {:error, :not_found}

      visitor ->
        case get_active_pass_for_visitor(scope, visitor.id) do
          nil -> {:error, :no_active_pass}
          pass -> {:ok, pass, visitor}
        end
    end
  end

  defp resolve_subject(scope, %{subject_type: "vehicle", subject_id: vehicle_id}) do
    vehicle_id = String.to_integer(vehicle_id)

    case Vehicle |> Tenancy.scope(scope) |> preload(:visitor) |> Repo.get(vehicle_id) do
      nil -> {:error, :not_found}
      vehicle -> {:ok, vehicle, vehicle}
    end
  end

  defp resolve_subject(_scope, _identifier), do: {:error, :not_found}

  @doc """
  Records a scan at `access_point` for `subject` (a `%VisitorPass{}` or
  `%Vehicle{}`), enforcing that the pass/vehicle is currently valid and
  that direction alternates: a subject already logged `in` cannot be
  logged `in` again without an `out` in between. Broadcasts the accepted
  scan on `"org:{id}:access_logs"`.
  """
  def record_scan(%Scope{} = scope, access_point, subject, direction, operator \\ nil)
      when direction in ["in", "out"] do
    ensure_same_organization!(scope, access_point)
    subject_type = subject_type_for(subject)

    with :ok <- validate_subject_status(subject),
         :ok <- validate_direction(scope, subject_type, subject.id, direction) do
      %AccessLog{}
      |> AccessLog.changeset(%{
        subject_type: subject_type,
        subject_id: subject.id,
        direction: direction,
        scanned_at: DateTime.utc_now() |> DateTime.truncate(:second),
        organization_id: Tenancy.organization_id!(scope),
        access_point_id: access_point.id,
        operator_id: operator && operator.id
      })
      |> Repo.insert()
      |> case do
        {:ok, log} ->
          broadcast_access_log(scope, %{log | access_point: access_point})
          {:ok, log}

        error ->
          error
      end
    end
  end

  def list_access_logs(%Scope{} = scope) do
    AccessLog
    |> Tenancy.scope(scope)
    |> preload(:access_point)
    |> order_by([l], desc: l.scanned_at)
    |> Repo.all()
  end

  @doc "The last recorded direction for a subject, or nil if it has never been scanned."
  def last_direction(%Scope{} = scope, subject_type, subject_id) do
    AccessLog
    |> Tenancy.scope(scope)
    |> where([l], l.subject_type == ^subject_type and l.subject_id == ^subject_id)
    |> order_by([l], desc: l.scanned_at)
    |> limit(1)
    |> select([l], l.direction)
    |> Repo.one()
  end

  @doc """
  Everyone and every vehicle currently on-site: the subject of the most
  recent access log per (subject_type, subject_id), where that log's
  direction is `"in"`. Each entry carries the display name and, for
  visitors, their host.
  """
  def list_onsite(%Scope{} = scope) do
    AccessLog
    |> Tenancy.scope(scope)
    |> distinct([l], [l.subject_type, l.subject_id])
    |> order_by([l], asc: l.subject_type, asc: l.subject_id, desc: l.scanned_at)
    |> preload(:access_point)
    |> Repo.all()
    |> Enum.filter(&(&1.direction == "in"))
    |> Enum.map(&onsite_entry(scope, &1))
    |> Enum.sort_by(& &1.log.scanned_at, {:desc, DateTime})
  end

  defp onsite_entry(scope, %AccessLog{subject_type: "visitor_pass", subject_id: pass_id} = log) do
    case VisitorPass |> Tenancy.scope(scope) |> preload(:visitor) |> Repo.get(pass_id) do
      nil -> %{log: log, name: "Unknown visitor", host: nil, kind: :visitor}
      pass -> %{log: log, name: pass.visitor.name, host: pass.visitor.host, kind: :visitor}
    end
  end

  defp onsite_entry(scope, %AccessLog{subject_type: "vehicle", subject_id: vehicle_id} = log) do
    case Vehicle |> Tenancy.scope(scope) |> Repo.get(vehicle_id) do
      nil -> %{log: log, name: "Unknown vehicle", host: nil, kind: :vehicle}
      vehicle -> %{log: log, name: vehicle.plate, host: nil, kind: :vehicle}
    end
  end

  @overdue_hours 12

  @doc """
  Operational alerts for the organisation: visitors who have been on-site
  longer than expected, and sites at or over capacity. Denied-scan alerts
  are pushed live from the scanning view rather than computed here, since
  a rejected scan is never persisted as an access log.
  """
  def list_alerts(%Scope{} = scope) do
    onsite = list_onsite(scope)
    now = DateTime.utc_now()

    overdue =
      onsite
      |> Enum.filter(&(DateTime.diff(now, &1.log.scanned_at, :hour) >= @overdue_hours))
      |> Enum.map(&%{type: :overdue, entry: &1})

    capacity =
      onsite
      |> Enum.group_by(& &1.log.access_point.site_id)
      |> Enum.flat_map(fn {site_id, entries} ->
        capacity_alert(scope, site_id, length(entries))
      end)

    overdue ++ capacity
  end

  defp capacity_alert(scope, site_id, onsite_count) do
    case Site |> Tenancy.scope(scope) |> Repo.get(site_id) do
      %Site{capacity: capacity, name: name}
      when is_integer(capacity) and onsite_count >= capacity ->
        [%{type: :capacity, site_name: name, onsite_count: onsite_count, capacity: capacity}]

      _ ->
        []
    end
  end

  defp broadcast_access_log(scope, log) do
    org_id = Tenancy.organization_id!(scope)
    Phoenix.PubSub.broadcast(Datem.PubSub, access_logs_topic(org_id), {:access_log_created, log})
  end

  @doc "The PubSub topic carrying live access-log activity for an organisation."
  def access_logs_topic(organization_id), do: "org:#{organization_id}:access_logs"

  defp next_direction(scope, subject) do
    subject_type = subject_type_for(subject)

    case last_direction(scope, subject_type, subject.id) do
      "in" -> "out"
      _ -> "in"
    end
  end

  defp validate_subject_status(%VisitorPass{status: "revoked"}), do: {:error, :revoked}

  defp validate_subject_status(%VisitorPass{valid_to: valid_to}) do
    if DateTime.compare(DateTime.utc_now(), valid_to) == :gt do
      {:error, :expired}
    else
      :ok
    end
  end

  defp validate_subject_status(%Vehicle{status: "revoked"}), do: {:error, :revoked}
  defp validate_subject_status(%Vehicle{}), do: :ok

  defp validate_direction(scope, subject_type, subject_id, direction) do
    case {last_direction(scope, subject_type, subject_id), direction} do
      {"in", "in"} -> {:error, :already_inside}
      {nil, "out"} -> {:error, :not_inside}
      {"out", "out"} -> {:error, :not_inside}
      _ -> :ok
    end
  end

  defp subject_type_for(%VisitorPass{}), do: "visitor_pass"
  defp subject_type_for(%Vehicle{}), do: "vehicle"

  ## Shared helpers

  defp ensure_same_organization!(%Scope{} = scope, resource) do
    if resource.organization_id != Tenancy.organization_id!(scope) do
      raise Ecto.NoResultsError, queryable: resource.__struct__
    end
  end

  defp random_token do
    16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end
end
