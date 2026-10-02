defmodule Datem.Ticketing do
  @moduledoc """
  The Ticketing context: events, ticket types, ticket registrations, and the
  check-in/check-out scans they generate.

  Identifier issuance (GSRN) and QR rendering are delegated to `Datem.GS1`,
  the same as `Datem.Access` does for visitor passes.
  """

  import Ecto.Query, warn: false

  alias Datem.Repo
  alias Datem.Accounts.Scope
  alias Datem.GS1
  alias Datem.Tenancy
  alias Datem.Organizations.Organization

  alias Datem.Ticketing.{
    Event,
    EventContentItem,
    EventScheduleItem,
    TicketType,
    Ticket,
    TicketScan,
    TicketMailerWorker
  }

  alias Datem.Reporting.CSV

  ## Events

  def list_events(%Scope{} = scope) do
    Event |> Tenancy.scope(scope) |> order_by([e], desc: e.starts_at) |> Repo.all()
  end

  def get_event_for_scope!(%Scope{} = scope, id) do
    Event |> Tenancy.scope(scope) |> preload(:ticket_types) |> Repo.get!(id)
  end

  def change_event(%Event{} = event, attrs \\ %{}), do: Event.changeset(event, attrs)

  def create_event(%Scope{} = scope, attrs) do
    %Event{}
    |> Event.changeset(Map.put(attrs, "organization_id", Tenancy.organization_id!(scope)))
    |> Repo.insert()
  end

  def update_event(%Scope{} = scope, %Event{} = event, attrs) do
    ensure_same_organization!(scope, event)
    event |> Event.changeset(attrs) |> Repo.update()
  end

  @doc "Generates (or replaces) the shareable public join-link token for an event."
  def create_join_link(%Scope{} = scope, %Event{} = event) do
    ensure_same_organization!(scope, event)
    event |> Event.join_link_changeset(random_token()) |> Repo.update()
  end

  @doc "Looks up an event by its public join-link token. Returns nil if unknown."
  def get_event_by_join_token(token) when is_binary(token) do
    Event
    |> where([e], e.join_link_token == ^token)
    |> preload([:organization, :ticket_types])
    |> Repo.one()
  end

  ## Ticket types

  def list_ticket_types(%Scope{} = scope, %Event{} = event) do
    ensure_same_organization!(scope, event)

    TicketType
    |> Tenancy.scope(scope)
    |> where([t], t.event_id == ^event.id)
    |> order_by([t], asc: t.name)
    |> Repo.all()
  end

  def change_ticket_type(%TicketType{} = ticket_type, attrs \\ %{}),
    do: TicketType.changeset(ticket_type, attrs)

  def create_ticket_type(%Scope{} = scope, %Event{} = event, attrs) do
    ensure_same_organization!(scope, event)

    %TicketType{}
    |> TicketType.changeset(
      Map.merge(attrs, %{
        "organization_id" => Tenancy.organization_id!(scope),
        "event_id" => event.id
      })
    )
    |> Repo.insert()
  end

  ## Tickets / registrations

  def list_tickets(%Scope{} = scope, %Event{} = event) do
    ensure_same_organization!(scope, event)

    Ticket
    |> Tenancy.scope(scope)
    |> where([t], t.event_id == ^event.id)
    |> preload(:ticket_type)
    |> order_by([t], desc: t.inserted_at)
    |> Repo.all()
  end

  def get_ticket_for_scope!(%Scope{} = scope, id) do
    Ticket
    |> Tenancy.scope(scope)
    |> preload([:event, :ticket_type, :gs1_identifier])
    |> Repo.get!(id)
  end

  def update_ticket(%Scope{} = scope, %Ticket{} = ticket, attrs) do
    ensure_same_organization!(scope, ticket)
    event = Repo.get!(Event, ticket.event_id)

    ticket
    |> Ticket.changeset(attrs, event.required_attendee_fields)
    |> Repo.update()
  end

  def count_missing_field(%Scope{} = scope, %Event{} = event, field) when is_binary(field) do
    if field in Ticket.attendee_detail_fields() do
      field_atom = String.to_existing_atom(field)

      Ticket
      |> Tenancy.scope(scope)
      |> where([t], t.event_id == ^event.id)
      |> where([t], is_nil(field(t, ^field_atom)))
      |> select([t], count(t.id))
      |> Repo.one()
    else
      0
    end
  end

  def count_missing_field(%Scope{} = scope, %Event{} = event, _field) do
    count_missing_field(scope, event, "")
  end

  def get_ticket_by_gsrn(gsrn) when is_binary(gsrn) do
    Ticket
    |> join(:inner, [t], i in assoc(t, :gs1_identifier))
    |> where([t, i], i.value == ^gsrn)
    |> preload([:event, :ticket_type, :gs1_identifier])
    |> Repo.one()
  end

  def list_content_items(%Scope{} = scope, %Event{} = event) do
    ensure_same_organization!(scope, event)

    EventContentItem
    |> Tenancy.scope(scope)
    |> where([i], i.event_id == ^event.id)
    |> order_by([i], asc: i.position, asc: i.id)
    |> Repo.all()
  end

  def get_content_item_for_scope!(%Scope{} = scope, id) do
    EventContentItem |> Tenancy.scope(scope) |> Repo.get!(id)
  end

  def change_content_item(%EventContentItem{} = item, attrs \\ %{}),
    do: EventContentItem.changeset(item, attrs)

  def create_content_item(%Scope{} = scope, %Event{} = event, attrs) do
    ensure_same_organization!(scope, event)

    %EventContentItem{}
    |> EventContentItem.changeset(
      Map.merge(attrs, %{
        "organization_id" => Tenancy.organization_id!(scope),
        "event_id" => event.id
      })
    )
    |> Repo.insert()
  end

  def update_content_item(%Scope{} = scope, %EventContentItem{} = item, attrs) do
    ensure_same_organization!(scope, item)
    item |> EventContentItem.changeset(attrs) |> Repo.update()
  end

  def delete_content_item(%Scope{} = scope, %EventContentItem{} = item) do
    ensure_same_organization!(scope, item)
    Repo.delete(item)
  end

  @doc "Public, unauthenticated: active content items for an event's public ticket page."
  def list_public_content_items(event_id) do
    EventContentItem
    |> where([i], i.event_id == ^event_id and i.is_active == true)
    |> order_by([i], asc: i.position, asc: i.id)
    |> Repo.all()
  end

  ## Schedule

  def list_schedule_items(%Scope{} = scope, %Event{} = event) do
    ensure_same_organization!(scope, event)

    EventScheduleItem
    |> Tenancy.scope(scope)
    |> where([i], i.event_id == ^event.id)
    |> order_by([i], asc: i.starts_at, asc: i.position, asc: i.id)
    |> Repo.all()
  end

  def get_schedule_item_for_scope!(%Scope{} = scope, id) do
    EventScheduleItem |> Tenancy.scope(scope) |> Repo.get!(id)
  end

  def change_schedule_item(%EventScheduleItem{} = item, attrs \\ %{}),
    do: EventScheduleItem.changeset(item, attrs)

  def create_schedule_item(%Scope{} = scope, %Event{} = event, attrs) do
    ensure_same_organization!(scope, event)

    %EventScheduleItem{}
    |> EventScheduleItem.changeset(
      Map.merge(attrs, %{
        "organization_id" => Tenancy.organization_id!(scope),
        "event_id" => event.id
      })
    )
    |> Repo.insert()
  end

  def update_schedule_item(%Scope{} = scope, %EventScheduleItem{} = item, attrs) do
    ensure_same_organization!(scope, item)
    item |> EventScheduleItem.changeset(attrs) |> Repo.update()
  end

  def delete_schedule_item(%Scope{} = scope, %EventScheduleItem{} = item) do
    ensure_same_organization!(scope, item)
    Repo.delete(item)
  end

  @doc "Public, unauthenticated: active schedule items for an event's public ticket page."
  def list_public_schedule_items(event_id) do
    EventScheduleItem
    |> where([i], i.event_id == ^event_id and i.is_active == true)
    |> order_by([i], asc: i.starts_at, asc: i.position, asc: i.id)
    |> Repo.all()
  end

  @doc """
  Groups schedule items by calendar day (Nairobi local time) for display.
  Returns a list of `%{date: Date.t(), label: String.t() | nil, items: [item]}`
  sorted chronologically.
  """
  def group_schedule_by_day(items) when is_list(items) do
    items
    |> Enum.group_by(fn item ->
      item.starts_at |> Datem.NairobiTime.to_local() |> DateTime.to_date()
    end)
    |> Enum.sort_by(fn {date, _} -> date end, Date)
    |> Enum.map(fn {date, day_items} ->
      label =
        day_items
        |> Enum.find_value(fn item ->
          label = item.day_label && String.trim(item.day_label)
          if label != "", do: label
        end)

      %{date: date, label: label, items: day_items}
    end)
  end

  def import_attendees(%Event{} = event, %TicketType{} = ticket_type, csv_binary) do
    {header, rows} = CSV.decode(csv_binary)

    rows
    |> Enum.with_index(2)
    |> Enum.reduce({0, []}, fn {row, line_number}, {ok_count, errors} ->
      attrs = header |> Enum.zip(row) |> Map.new() |> row_to_attrs()

      case register_attendee(event, ticket_type, attrs) do
        {:ok, _ticket} ->
          {ok_count + 1, errors}

        {:error, :sold_out} ->
          {ok_count, [{line_number, "sold out"} | errors]}

        {:error, changeset} ->
          {ok_count, [{line_number, changeset_error_summary(changeset)} | errors]}
      end
    end)
    |> then(fn {ok_count, errors} -> {ok_count, Enum.reverse(errors)} end)
  end

  defp row_to_attrs(row) do
    %{
      "attendee_name" => row["name"],
      "attendee_email" => row["email"],
      "company" => row["company"],
      "id_number" => row["id_number"],
      "phone_number" => row["phone_number"],
      "gender" => row["gender"],
      "dob" => row["dob"]
    }
  end

  defp changeset_error_summary(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, _opts} -> msg end)
    |> Enum.map_join(", ", fn {field, msgs} -> "#{field}: #{Enum.join(msgs, ", ")}" end)
  end

  def set_event_status(%Scope{} = scope, %Event{} = event, status) do
    ensure_same_organization!(scope, event)

    if status in Event.statuses() do
      event |> Event.status_changeset(status) |> Repo.update()
    else
      {:error, :invalid_status}
    end
  end

  @doc """
  Registers an attendee for `ticket_type` at `event`: issues a GSRN ticket
  identifier and enqueues an email with the QR code. Runs as a public,
  unauthenticated action (from a join link), so it takes the event/ticket
  type directly rather than a caller `%Scope{}`, and builds one internally
  scoped to the organisation that owns the event.

  Rejects registration once the ticket type's `quantity` is exhausted.
  """
  def register_attendee(%Event{} = event, %TicketType{} = ticket_type, attrs) do
    scope = %Scope{organization: event_organization(event)}

    Repo.transact(fn ->
      with :ok <- check_availability(ticket_type),
           {:ok, ticket} <-
             %Ticket{}
             |> Ticket.changeset(
               Map.merge(attrs, %{
                 "organization_id" => Tenancy.organization_id!(scope),
                 "event_id" => event.id,
                 "ticket_type_id" => ticket_type.id
               }),
               event.required_attendee_fields
             )
             |> Repo.insert(),
           {:ok, identifier} <- GS1.issue_identifier(scope, :gsrn, "ticket", ticket.id),
           {:ok, ticket} <-
             ticket |> Ticket.gs1_identifier_changeset(identifier.id) |> Repo.update() do
        {:ok, %{ticket | gs1_identifier: identifier}}
      end
    end)
    |> case do
      {:ok, ticket} ->
        %{"ticket_id" => ticket.id} |> TicketMailerWorker.new() |> Oban.insert()
        {:ok, ticket}

      error ->
        error
    end
  end

  defp check_availability(%TicketType{quantity: nil}), do: :ok

  defp check_availability(%TicketType{id: id, quantity: quantity}) do
    issued =
      Ticket
      |> where([t], t.ticket_type_id == ^id and t.status != "cancelled")
      |> select([t], count(t.id))
      |> Repo.one()

    if issued < quantity, do: :ok, else: {:error, :sold_out}
  end

  ## Scanning (check-in / check-out)

  @doc """
  Resolves a scanned GS1 Digital Link to the ticket it names and records a
  check-in/out scan at `event`, automatically alternating direction based
  on the ticket's last recorded scan. Rejects a cancelled ticket or a code
  belonging to a different event/organisation.
  """
  def scan(%Scope{} = scope, %Event{} = event, digital_link, operator \\ nil) do
    with {:ok, ticket} <- resolve_scan_subject(scope, event, digital_link) do
      direction = next_direction(scope, ticket)

      case record_scan(scope, event, ticket, direction, operator) do
        {:ok, log, ticket} -> {:ok, log, ticket, direction}
        {:error, reason} -> {:error, reason, ticket}
      end
    end
  end

  def resolve_scan_subject(%Scope{} = scope, %Event{} = event, digital_link)
      when is_binary(digital_link) do
    ensure_same_organization!(scope, event)

    with {:ok, identifier} <- GS1.resolve_digital_link(scope, digital_link) do
      resolve_subject(scope, event, identifier)
    end
  end

  defp resolve_subject(scope, %Event{id: event_id}, %{
         subject_type: "ticket",
         subject_id: ticket_id
       }) do
    ticket_id = String.to_integer(ticket_id)

    case Ticket |> Tenancy.scope(scope) |> Repo.get(ticket_id) do
      %Ticket{event_id: ^event_id} = ticket -> {:ok, ticket}
      %Ticket{} -> {:error, :wrong_event}
      nil -> {:error, :not_found}
    end
  end

  defp resolve_subject(_scope, _event, _identifier), do: {:error, :not_found}

  @doc """
  Records a check-in/out scan for `ticket` at `event`, enforcing that the
  ticket isn't cancelled and that direction alternates. Broadcasts the
  accepted scan and updates the ticket's status.
  """
  def record_scan(
        %Scope{} = scope,
        %Event{} = event,
        %Ticket{} = ticket,
        direction,
        operator \\ nil
      )
      when direction in ["in", "out"] do
    ensure_same_organization!(scope, event)
    ensure_same_organization!(scope, ticket)

    with :ok <- validate_ticket_status(ticket),
         :ok <- validate_direction(scope, ticket.id, direction) do
      Repo.transact(fn ->
        with {:ok, log} <-
               %TicketScan{}
               |> TicketScan.changeset(%{
                 direction: direction,
                 scanned_at: DateTime.utc_now() |> DateTime.truncate(:second),
                 organization_id: Tenancy.organization_id!(scope),
                 event_id: event.id,
                 ticket_id: ticket.id,
                 operator_id: operator && operator.id
               })
               |> Repo.insert(),
             {:ok, ticket} <-
               ticket |> Ticket.status_changeset(ticket_status_for(direction)) |> Repo.update() do
          {:ok, {log, ticket}}
        end
      end)
      |> case do
        {:ok, {log, ticket}} ->
          broadcast_scan(scope, event, log, ticket)
          {:ok, log, ticket}

        error ->
          error
      end
    end
  end

  @doc "The last recorded direction for a ticket, or nil if it has never been scanned."
  def last_direction(%Scope{} = scope, ticket_id) do
    TicketScan
    |> Tenancy.scope(scope)
    |> where([s], s.ticket_id == ^ticket_id)
    |> order_by([s], desc: s.scanned_at)
    |> limit(1)
    |> select([s], s.direction)
    |> Repo.one()
  end

  @doc "Registered vs checked-in counts and the live feed for an event's dashboard."
  def event_stats(%Scope{} = scope, %Event{} = event) do
    ensure_same_organization!(scope, event)
    tickets = list_tickets(scope, event)

    %{
      registered: length(tickets),
      checked_in: Enum.count(tickets, &(&1.status == "checked_in")),
      by_ticket_type: Enum.group_by(tickets, & &1.ticket_type.name)
    }
  end

  @doc "Re-sends the ticket confirmation email (QR + event details) via the same worker used at registration."
  def resend_ticket_email(%Scope{} = scope, %Ticket{} = ticket) do
    ensure_same_organization!(scope, ticket)
    %{"ticket_id" => ticket.id} |> TicketMailerWorker.new() |> Oban.insert()
  end

  def list_recent_scans(%Scope{} = scope, %Event{} = event, limit \\ 20) do
    ensure_same_organization!(scope, event)

    TicketScan
    |> Tenancy.scope(scope)
    |> where([s], s.event_id == ^event.id)
    |> order_by([s], desc: s.scanned_at)
    |> limit(^limit)
    |> preload(:ticket)
    |> Repo.all()
  end

  defp broadcast_scan(scope, event, log, ticket) do
    org_id = Tenancy.organization_id!(scope)

    Phoenix.PubSub.broadcast(
      Datem.PubSub,
      event_topic(org_id, event.id),
      {:ticket_scanned, %{log | ticket: ticket}}
    )
  end

  @doc "The PubSub topic carrying live scan activity for an event."
  def event_topic(organization_id, event_id), do: "org:#{organization_id}:event:#{event_id}"

  defp next_direction(scope, ticket) do
    case last_direction(scope, ticket.id) do
      "in" -> "out"
      _ -> "in"
    end
  end

  defp validate_ticket_status(%Ticket{status: "cancelled"}), do: {:error, :cancelled}
  defp validate_ticket_status(%Ticket{}), do: :ok

  defp validate_direction(scope, ticket_id, direction) do
    case {last_direction(scope, ticket_id), direction} do
      {"in", "in"} -> {:error, :already_inside}
      {nil, "out"} -> {:error, :not_inside}
      {"out", "out"} -> {:error, :not_inside}
      _ -> :ok
    end
  end

  defp ticket_status_for("in"), do: "checked_in"
  defp ticket_status_for("out"), do: "checked_out"

  ## Shared helpers

  defp ensure_same_organization!(%Scope{} = scope, resource) do
    if resource.organization_id != Tenancy.organization_id!(scope) do
      raise Ecto.NoResultsError, queryable: resource.__struct__
    end
  end

  defp random_token do
    16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end

  @doc false
  def event_organization(%Event{organization: %Organization{} = organization}), do: organization
  def event_organization(%Event{organization_id: id}), do: Repo.get!(Organization, id)
end
