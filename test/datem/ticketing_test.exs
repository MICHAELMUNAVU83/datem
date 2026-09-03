defmodule Datem.TicketingTest do
  use Datem.DataCase, async: true

  import Swoosh.TestAssertions

  alias Datem.Ticketing
  alias Datem.Ticketing.{Event, TicketType, Ticket}

  import Datem.OrganizationsFixtures

  defp event_fixture(scope, attrs \\ %{}) do
    {:ok, event} = Ticketing.create_event(scope, Enum.into(attrs, %{"name" => "Conference 2026"}))
    event
  end

  defp ticket_type_fixture(scope, event, attrs \\ %{}) do
    {:ok, ticket_type} =
      Ticketing.create_ticket_type(scope, event, Enum.into(attrs, %{"name" => "General"}))

    ticket_type
  end

  describe "events" do
    test "create_event/2 scopes the event to the caller's organisation" do
      scope = owner_scope_fixture()

      assert {:ok, %Event{} = event} =
               Ticketing.create_event(scope, %{"name" => "Conference 2026"})

      assert event.organization_id == scope.organization.id
      assert event.status == "draft"
    end

    test "list_events/1 is tenant scoped" do
      scope_a = owner_scope_fixture()
      scope_b = owner_scope_fixture()

      event_a = event_fixture(scope_a)
      event_fixture(scope_b)

      assert [%Event{id: id}] = Ticketing.list_events(scope_a)
      assert id == event_a.id
    end

    test "get_event_for_scope!/2 raises for an event belonging to another organisation" do
      scope_a = owner_scope_fixture()
      scope_b = owner_scope_fixture()

      event_b = event_fixture(scope_b)

      assert_raise Ecto.NoResultsError, fn ->
        Ticketing.get_event_for_scope!(scope_a, event_b.id)
      end
    end

    test "create_join_link/2 then get_event_by_join_token/1 resolves the event" do
      scope = owner_scope_fixture()
      event = event_fixture(scope)

      assert {:ok, event} = Ticketing.create_join_link(scope, event)
      assert event.join_link_token

      found = Ticketing.get_event_by_join_token(event.join_link_token)
      assert found.id == event.id
    end

    test "get_event_by_join_token/1 returns nil for an unknown token" do
      refute Ticketing.get_event_by_join_token("does-not-exist")
    end
  end

  describe "ticket types" do
    test "create_ticket_type/3 scopes it to the event and organisation" do
      scope = owner_scope_fixture()
      event = event_fixture(scope)

      assert {:ok, %TicketType{} = ticket_type} =
               Ticketing.create_ticket_type(scope, event, %{"name" => "VIP", "quantity" => 10})

      assert ticket_type.event_id == event.id
      assert ticket_type.organization_id == scope.organization.id
    end

    test "list_ticket_types/2 raises for an event belonging to another organisation" do
      scope_a = owner_scope_fixture()
      scope_b = owner_scope_fixture()
      event_b = event_fixture(scope_b)

      assert_raise Ecto.NoResultsError, fn -> Ticketing.list_ticket_types(scope_a, event_b) end
    end
  end

  describe "register_attendee/3" do
    test "issues a GSRN ticket and enqueues the confirmation email" do
      scope = owner_scope_fixture()
      event = event_fixture(scope)
      ticket_type = ticket_type_fixture(scope, event)

      assert {:ok, %Ticket{} = ticket} =
               Ticketing.register_attendee(event, ticket_type, %{
                 "attendee_name" => "Jane Doe",
                 "attendee_email" => "jane@example.com"
               })

      assert ticket.status == "registered"
      assert ticket.gs1_identifier.kind == :gsrn
      assert_email_sent(subject: "Your ticket for #{event.name}")
    end

    test "rejects registration once the ticket type is sold out" do
      scope = owner_scope_fixture()
      event = event_fixture(scope)
      ticket_type = ticket_type_fixture(scope, event, %{"quantity" => 1})

      assert {:ok, _ticket} =
               Ticketing.register_attendee(event, ticket_type, %{"attendee_name" => "First"})

      assert {:error, :sold_out} =
               Ticketing.register_attendee(event, ticket_type, %{"attendee_name" => "Second"})
    end
  end

  describe "scan/4" do
    test "checks a ticket in and alternates direction on repeated scans" do
      scope = owner_scope_fixture()
      event = event_fixture(scope)
      ticket_type = ticket_type_fixture(scope, event)

      {:ok, ticket} =
        Ticketing.register_attendee(event, ticket_type, %{"attendee_name" => "Jane Doe"})

      code = ticket.gs1_identifier.digital_link

      assert {:ok, _log, _ticket, "in"} = Ticketing.scan(scope, event, code)
      assert {:ok, _log, _ticket, "out"} = Ticketing.scan(scope, event, code)
    end

    test "rejects a duplicate check-in" do
      scope = owner_scope_fixture()
      event = event_fixture(scope)
      ticket_type = ticket_type_fixture(scope, event)

      {:ok, ticket} =
        Ticketing.register_attendee(event, ticket_type, %{"attendee_name" => "Jane Doe"})

      code = ticket.gs1_identifier.digital_link

      assert {:ok, _log, _ticket, "in"} = Ticketing.scan(scope, event, code)
      assert {:error, :already_inside, _ticket} = Ticketing.scan(scope, event, code)
    end

    test "rejects a code issued by another organisation" do
      scope_a = owner_scope_fixture()
      scope_b = owner_scope_fixture()
      event_a = event_fixture(scope_a)
      event_b = event_fixture(scope_b)
      ticket_type_b = ticket_type_fixture(scope_b, event_b)

      {:ok, ticket_b} =
        Ticketing.register_attendee(event_b, ticket_type_b, %{"attendee_name" => "Jane Doe"})

      assert {:error, :not_found} =
               Ticketing.resolve_scan_subject(
                 scope_a,
                 event_a,
                 ticket_b.gs1_identifier.digital_link
               )
    end

    test "rejects a ticket scanned at a different event" do
      scope = owner_scope_fixture()
      event = event_fixture(scope)
      other_event = event_fixture(scope)
      ticket_type = ticket_type_fixture(scope, event)

      {:ok, ticket} =
        Ticketing.register_attendee(event, ticket_type, %{"attendee_name" => "Jane Doe"})

      assert {:error, :wrong_event, _ticket} =
               Ticketing.scan(scope, other_event, ticket.gs1_identifier.digital_link)
    end
  end

  describe "event_stats/2" do
    test "reports registered vs checked-in counts" do
      scope = owner_scope_fixture()
      event = event_fixture(scope)
      ticket_type = ticket_type_fixture(scope, event)

      {:ok, ticket_a} = Ticketing.register_attendee(event, ticket_type, %{"attendee_name" => "A"})

      {:ok, _ticket_b} =
        Ticketing.register_attendee(event, ticket_type, %{"attendee_name" => "B"})

      Ticketing.scan(scope, event, ticket_a.gs1_identifier.digital_link)

      assert %{registered: 2, checked_in: 1} = Ticketing.event_stats(scope, event)
    end
  end
end
