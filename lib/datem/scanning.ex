defmodule Datem.Scanning do
  @moduledoc """
  The shared scanning engine: configurable scan types (checkpoints) and the
  scan logs they produce.

  A scan follows one path regardless of which module it came from:

      parse Digital Link -> resolve subject in tenant scope -> evaluate rules
        -> write scan_log -> broadcast

  Because the rules live in `scan_types.rules` (JSONB), a new checkpoint —
  "Lunch", "Welcome pack", "Session A" — is configuration, not code.
  """

  import Ecto.Query, warn: false

  alias Datem.Access
  alias Datem.Access.{Site, Vehicle, VisitorPass}
  alias Datem.Accounts.Scope
  alias Datem.GS1
  alias Datem.Repo
  alias Datem.Scanning.{ScanLog, ScanType}
  alias Datem.Tenancy
  alias Datem.Ticketing.{Event, Ticket}

  ## Scan types

  def list_scan_types(%Scope{} = scope) do
    ScanType |> Tenancy.scope(scope) |> base_scan_type_query() |> Repo.all()
  end

  @doc "Scan types configured for `event` or `site`, newest-named-first."
  def list_scan_types_for(%Scope{} = scope, %Event{} = event) do
    ensure_same_organization!(scope, event)

    ScanType
    |> Tenancy.scope(scope)
    |> where([s], s.event_id == ^event.id)
    |> base_scan_type_query()
    |> Repo.all()
  end

  def list_scan_types_for(%Scope{} = scope, %Site{} = site) do
    ensure_same_organization!(scope, site)

    ScanType
    |> Tenancy.scope(scope)
    |> where([s], s.site_id == ^site.id)
    |> base_scan_type_query()
    |> Repo.all()
  end

  @doc "Scan types an operator can currently pick from: active, and inside their window."
  def list_scannable_scan_types(%Scope{} = scope, now \\ nil) do
    now = now || DateTime.utc_now()

    ScanType
    |> Tenancy.scope(scope)
    |> where([s], s.active)
    |> where([s], is_nil(s.active_from) or s.active_from <= ^now)
    |> where([s], is_nil(s.active_to) or s.active_to >= ^now)
    |> base_scan_type_query()
    |> Repo.all()
  end

  def get_scan_type_for_scope!(%Scope{} = scope, id) do
    ScanType |> Tenancy.scope(scope) |> preload([:event, :site]) |> Repo.get!(id)
  end

  def change_scan_type(%ScanType{} = scan_type, attrs \\ %{}),
    do: ScanType.changeset(scan_type, attrs)

  def create_scan_type(%Scope{} = scope, attrs) do
    %ScanType{}
    |> ScanType.changeset(put_organization(scope, attrs))
    |> Repo.insert()
  end

  def update_scan_type(%Scope{} = scope, %ScanType{} = scan_type, attrs) do
    ensure_same_organization!(scope, scan_type)
    scan_type |> ScanType.changeset(attrs) |> Repo.update()
  end

  def set_active(%Scope{} = scope, %ScanType{} = scan_type, active) do
    ensure_same_organization!(scope, scan_type)
    scan_type |> ScanType.active_changeset(active) |> Repo.update()
  end

  defp base_scan_type_query(query) do
    query |> order_by([s], asc: s.name) |> preload([:event, :site])
  end

  defp put_organization(scope, attrs) do
    Map.put(attrs, "organization_id", Tenancy.organization_id!(scope))
  end

  ## Scanning

  @doc """
  Scans `digital_link` at `scan_type`.

  Resolves the code to a subject inside the caller's tenant, evaluates the
  scan type's rules, and always writes a `scan_log` — accepted or not, the
  attempt is part of the audit trail. Returns
  `{:ok, %{result: result, message: message, subject: subject, label: label, log: log}}`,
  or `{:error, reason}` when the code can't be resolved to a subject at all.
  """
  def scan(%Scope{} = scope, %ScanType{} = scan_type, digital_link, operator \\ nil)
      when is_binary(digital_link) do
    ensure_same_organization!(scope, scan_type)

    with {:ok, subject, label} <- resolve_scan_subject(scope, scan_type, digital_link) do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      {result, message} = evaluate(scope, scan_type, subject, now)

      case write_log(scope, scan_type, subject, result, message, label, operator, now) do
        {:ok, log} ->
          broadcast(scope, %{log | scan_type: scan_type})
          {:ok, %{result: result, message: message, subject: subject, label: label, log: log}}

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  @doc """
  Resolves a scanned Digital Link to the subject it names, within tenant scope
  and within the scan type's own scope (an event checkpoint only accepts
  tickets for that event).
  """
  def resolve_scan_subject(%Scope{} = scope, %ScanType{} = scan_type, digital_link) do
    with {:ok, identifier} <- GS1.resolve_digital_link(scope, digital_link) do
      resolve_subject(scope, scan_type, identifier)
    end
  end

  defp resolve_subject(scope, scan_type, %{subject_type: "ticket", subject_id: ticket_id}) do
    query = Ticket |> Tenancy.scope(scope) |> preload([:ticket_type, :event])

    case Repo.get(query, String.to_integer(ticket_id)) do
      nil -> {:error, :not_found}
      %Ticket{} = ticket -> check_ticket_scope(scan_type, ticket)
    end
  end

  defp resolve_subject(scope, scan_type, %{subject_type: "visitor_pass"} = identifier) do
    # Visitor passes resolve through `Datem.Access`, which owns the rules about
    # which of a visitor's passes is currently the active one.
    with {:ok, %VisitorPass{} = pass, visitor} <-
           Access.resolve_scan_subject(scope, identifier.digital_link),
         :ok <- check_site_scope(scope, scan_type) do
      {:ok, pass, visitor.name}
    end
  end

  defp resolve_subject(scope, scan_type, %{subject_type: "vehicle"} = identifier) do
    with {:ok, %Vehicle{} = vehicle, _} <-
           Access.resolve_scan_subject(scope, identifier.digital_link),
         :ok <- check_site_scope(scope, scan_type) do
      {:ok, vehicle, vehicle.plate}
    end
  end

  defp resolve_subject(_scope, _scan_type, _identifier), do: {:error, :not_found}

  defp check_ticket_scope(%ScanType{event_id: nil}, %Ticket{}), do: {:error, :wrong_scope}

  defp check_ticket_scope(%ScanType{event_id: event_id}, %Ticket{event_id: event_id} = ticket),
    do: {:ok, ticket, ticket.attendee_name}

  defp check_ticket_scope(%ScanType{}, %Ticket{}), do: {:error, :wrong_event}

  defp check_site_scope(_scope, %ScanType{site_id: nil}), do: {:error, :wrong_scope}
  defp check_site_scope(_scope, %ScanType{}), do: :ok

  ## Rule engine

  @doc """
  Evaluates `scan_type`'s rules against `subject` at `now`, returning
  `{result, message}` where result is `:accepted`, `:duplicate`, `:expired`
  or `:denied`.

  Rules are checked cheapest-and-most-general first, so the operator always
  sees the most useful reason: the checkpoint being closed matters more than
  the attendee's ticket type, which matters more than a repeat scan.
  """
  def evaluate(%Scope{} = scope, %ScanType{} = scan_type, subject, now \\ nil) do
    now = now || DateTime.utc_now()
    rules = scan_type.rules || %ScanType.Rules{}

    with :ok <- check_active(scan_type),
         :ok <- check_window(scan_type, now),
         :ok <- check_subject_status(subject),
         :ok <- check_ticket_type(rules, subject),
         :ok <- check_prior_scan(scope, rules, subject),
         :ok <- check_once(scope, scan_type, rules, subject) do
      {:accepted, "#{scan_type.name} · #{Calendar.strftime(now, "%H:%M")}"}
    end
  end

  defp check_active(%ScanType{active: false}), do: {:denied, "This checkpoint is switched off"}
  defp check_active(%ScanType{}), do: :ok

  defp check_subject_status(%Ticket{status: "cancelled"}),
    do: {:denied, "This ticket has been cancelled"}

  defp check_subject_status(_subject), do: :ok

  defp check_window(%ScanType{active_from: nil, active_to: nil}, _now), do: :ok

  defp check_window(%ScanType{active_from: from, active_to: to} = scan_type, now) do
    cond do
      from && DateTime.compare(now, from) == :lt ->
        {:expired, "#{scan_type.name} opens at #{Calendar.strftime(from, "%H:%M")}"}

      to && DateTime.compare(now, to) == :gt ->
        {:expired, "#{scan_type.name} closed at #{Calendar.strftime(to, "%H:%M")}"}

      true ->
        :ok
    end
  end

  defp check_ticket_type(%{allowed_ticket_type_ids: ids}, _subject) when ids in [nil, []], do: :ok

  defp check_ticket_type(%{allowed_ticket_type_ids: ids}, %Ticket{} = ticket) do
    if ticket.ticket_type_id in ids do
      :ok
    else
      {:denied, "Not valid for #{ticket_type_name(ticket)} tickets"}
    end
  end

  # A ticket-type restriction can never be satisfied by a non-ticket subject.
  defp check_ticket_type(%{allowed_ticket_type_ids: _}, _subject),
    do: {:denied, "Only valid for event tickets"}

  defp check_prior_scan(scope, rules, subject) do
    with :ok <- check_check_in(rules, subject) do
      check_required_scan_type(scope, rules, subject)
    end
  end

  defp check_check_in(%{requires_check_in: true}, %Ticket{status: status})
       when status != "checked_in",
       do: {:denied, "Must be checked in to the event first"}

  defp check_check_in(%{requires_check_in: true}, %VisitorPass{}), do: :ok
  defp check_check_in(_rules, _subject), do: :ok

  defp check_required_scan_type(_scope, %{requires_prior_scan_type_id: nil}, _subject), do: :ok

  defp check_required_scan_type(scope, %{requires_prior_scan_type_id: prior_id}, subject) do
    if accepted_scan_exists?(scope, prior_id, subject) do
      :ok
    else
      {:denied, "Requires #{prior_scan_type_name(scope, prior_id)} first"}
    end
  end

  defp check_once(_scope, _scan_type, %{once_per_subject: false}, _subject), do: :ok

  defp check_once(scope, scan_type, _rules, subject) do
    case last_accepted_scan(scope, scan_type.id, subject) do
      nil ->
        :ok

      log ->
        {:duplicate, "Already claimed at #{Calendar.strftime(log.scanned_at, "%H:%M")}"}
    end
  end

  defp prior_scan_type_name(scope, prior_id) do
    ScanType
    |> Tenancy.scope(scope)
    |> where([s], s.id == ^prior_id)
    |> select([s], s.name)
    |> Repo.one() || "an earlier checkpoint"
  end

  ## Scan logs & tallies

  @doc "Whether `subject` already has an accepted scan at `scan_type_id`."
  def accepted_scan_exists?(%Scope{} = scope, scan_type_id, subject) do
    not is_nil(last_accepted_scan(scope, scan_type_id, subject))
  end

  defp last_accepted_scan(scope, scan_type_id, subject) do
    {subject_type, subject_id} = subject_ref(subject)

    ScanLog
    |> Tenancy.scope(scope)
    |> where([l], l.scan_type_id == ^scan_type_id and l.result == "accepted")
    |> where([l], l.subject_type == ^subject_type and l.subject_id == ^subject_id)
    |> order_by([l], desc: l.scanned_at)
    |> limit(1)
    |> Repo.one()
  end

  def list_recent_scans(%Scope{} = scope, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    ScanLog
    |> Tenancy.scope(scope)
    |> maybe_filter_scan_types(Keyword.get(opts, :scan_type_ids))
    |> order_by([l], desc: l.scanned_at, desc: l.id)
    |> limit(^limit)
    |> preload(:scan_type)
    |> Repo.all()
  end

  defp maybe_filter_scan_types(query, nil), do: query
  defp maybe_filter_scan_types(query, ids), do: where(query, [l], l.scan_type_id in ^ids)

  @doc """
  Accepted-scan tallies per scan type, e.g. 240 of 300 lunches claimed.

  The denominator for an event checkpoint is the number of live tickets it
  applies to (respecting an `allowed_ticket_type_ids` restriction); site
  checkpoints have no natural denominator, so `eligible` is nil there.
  """
  def tallies(%Scope{} = scope, scan_types) when is_list(scan_types) do
    counts = accepted_counts(scope, Enum.map(scan_types, & &1.id))

    Enum.map(scan_types, fn scan_type ->
      %{
        scan_type: scan_type,
        claimed: Map.get(counts, scan_type.id, 0),
        eligible: eligible_count(scope, scan_type)
      }
    end)
  end

  defp accepted_counts(_scope, []), do: %{}

  defp accepted_counts(scope, scan_type_ids) do
    ScanLog
    |> Tenancy.scope(scope)
    |> where([l], l.scan_type_id in ^scan_type_ids and l.result == "accepted")
    |> group_by([l], l.scan_type_id)
    |> select(
      [l],
      {l.scan_type_id, count(fragment("distinct (?, ?)", l.subject_type, l.subject_id))}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp eligible_count(_scope, %ScanType{event_id: nil}), do: nil

  defp eligible_count(scope, %ScanType{event_id: event_id, rules: rules}) do
    Ticket
    |> Tenancy.scope(scope)
    |> where([t], t.event_id == ^event_id and t.status != "cancelled")
    |> filter_ticket_types(rules && rules.allowed_ticket_type_ids)
    |> select([t], count(t.id))
    |> Repo.one()
  end

  defp filter_ticket_types(query, ids) when ids in [nil, []], do: query
  defp filter_ticket_types(query, ids), do: where(query, [t], t.ticket_type_id in ^ids)

  defp write_log(scope, scan_type, subject, result, message, label, operator, now) do
    {subject_type, subject_id} = subject_ref(subject)

    %ScanLog{}
    |> ScanLog.changeset(%{
      organization_id: Tenancy.organization_id!(scope),
      scan_type_id: scan_type.id,
      subject_type: subject_type,
      subject_id: subject_id,
      result: to_string(result),
      message: message,
      metadata: %{"label" => label},
      scanned_at: now,
      operator_id: operator && operator.id
    })
    |> Repo.insert()
  end

  defp subject_ref(%Ticket{id: id}), do: {"ticket", id}
  defp subject_ref(%VisitorPass{id: id}), do: {"visitor_pass", id}
  defp subject_ref(%Vehicle{id: id}), do: {"vehicle", id}

  defp ticket_type_name(%Ticket{ticket_type: %{name: name}}), do: name
  defp ticket_type_name(%Ticket{}), do: "these"

  ## Real-time

  @doc "The PubSub topic carrying every scan-engine result for an organisation."
  def topic(organization_id), do: "org:#{organization_id}:scan_logs"

  def subscribe(%Scope{} = scope) do
    Phoenix.PubSub.subscribe(Datem.PubSub, topic(Tenancy.organization_id!(scope)))
  end

  defp broadcast(scope, %ScanLog{} = log) do
    Phoenix.PubSub.broadcast(
      Datem.PubSub,
      topic(Tenancy.organization_id!(scope)),
      {:scan_logged, log}
    )
  end

  ## Shared helpers

  defp ensure_same_organization!(%Scope{} = scope, resource) do
    if resource.organization_id != Tenancy.organization_id!(scope) do
      raise Ecto.NoResultsError, queryable: resource.__struct__
    end
  end
end
