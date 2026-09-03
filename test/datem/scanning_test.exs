defmodule Datem.ScanningTest do
  use Datem.DataCase, async: true

  alias Datem.Scanning
  alias Datem.Scanning.{ScanLog, ScanType}
  alias Datem.Ticketing

  import Datem.OrganizationsFixtures

  defp event_fixture(scope, attrs \\ %{}) do
    {:ok, event} = Ticketing.create_event(scope, Enum.into(attrs, %{"name" => "Conference 2026"}))
    Ticketing.get_event_for_scope!(scope, event.id) |> Repo.preload(:organization)
  end

  defp ticket_type_fixture(scope, event, attrs \\ %{}) do
    {:ok, ticket_type} =
      Ticketing.create_ticket_type(scope, event, Enum.into(attrs, %{"name" => "General"}))

    ticket_type
  end

  defp ticket_fixture(event, ticket_type, attrs \\ %{}) do
    {:ok, ticket} =
      Ticketing.register_attendee(
        event,
        ticket_type,
        Enum.into(attrs, %{"attendee_name" => "Ada Lovelace"})
      )

    ticket
  end

  defp scan_type_fixture(scope, event, attrs \\ %{}) do
    {:ok, scan_type} =
      Scanning.create_scan_type(
        scope,
        Enum.into(attrs, %{"name" => "Lunch", "event_id" => event.id})
      )

    scan_type
  end

  defp code(ticket), do: ticket.gs1_identifier.digital_link

  defp check_in(scope, event, ticket) do
    {:ok, _log, ticket, _direction} = Ticketing.scan(scope, event, code(ticket), nil)
    ticket
  end

  defp setup_event do
    scope = owner_scope_fixture()
    event = event_fixture(scope)
    ticket_type = ticket_type_fixture(scope, event)

    %{
      scope: scope,
      event: event,
      ticket_type: ticket_type,
      ticket: ticket_fixture(event, ticket_type)
    }
  end

  describe "scan types" do
    test "create_scan_type/2 defaults to active, once-per-attendee rules" do
      %{scope: scope, event: event} = setup_event()

      assert {:ok, %ScanType{} = scan_type} =
               Scanning.create_scan_type(scope, %{"name" => "Lunch", "event_id" => event.id})

      assert scan_type.organization_id == scope.organization.id
      assert scan_type.active
      assert scan_type.rules.once_per_subject
      assert scan_type.rules.allowed_ticket_type_ids == []
    end

    test "create_scan_type/2 requires exactly one of event or site" do
      scope = owner_scope_fixture()

      assert {:error, changeset} = Scanning.create_scan_type(scope, %{"name" => "Lunch"})
      assert "pick an event or a site" in errors_on(changeset).event_id
    end

    test "create_scan_type/2 rejects a window that ends before it starts" do
      %{scope: scope, event: event} = setup_event()

      assert {:error, changeset} =
               Scanning.create_scan_type(scope, %{
                 "name" => "Lunch",
                 "event_id" => event.id,
                 "active_from" => ~U[2026-09-03 14:00:00Z],
                 "active_to" => ~U[2026-09-03 12:00:00Z]
               })

      assert "must be after the start of the window" in errors_on(changeset).active_to
    end

    test "list_scan_types/1 is tenant scoped" do
      %{scope: scope_a, event: event_a} = setup_event()
      %{scope: scope_b, event: event_b} = setup_event()

      scan_type_fixture(scope_a, event_a)
      scan_type_fixture(scope_b, event_b, %{"name" => "Other org lunch"})

      assert [%ScanType{name: "Lunch"}] = Scanning.list_scan_types(scope_a)
    end

    test "get_scan_type_for_scope!/2 raises for another organisation's scan type" do
      %{scope: scope_a} = setup_event()
      %{scope: scope_b, event: event_b} = setup_event()

      scan_type = scan_type_fixture(scope_b, event_b)

      assert_raise Ecto.NoResultsError, fn ->
        Scanning.get_scan_type_for_scope!(scope_a, scan_type.id)
      end
    end

    test "list_scannable_scan_types/1 excludes switched-off and out-of-window checkpoints" do
      %{scope: scope, event: event} = setup_event()

      open = scan_type_fixture(scope, event, %{"name" => "Open"})
      off = scan_type_fixture(scope, event, %{"name" => "Off"})
      {:ok, _} = Scanning.set_active(scope, off, false)

      scan_type_fixture(scope, event, %{
        "name" => "Later",
        "active_from" => DateTime.add(DateTime.utc_now(), 1, :hour)
      })

      assert [%ScanType{id: id}] = Scanning.list_scannable_scan_types(scope)
      assert id == open.id
    end
  end

  describe "scan/4 subject resolution" do
    test "resolves a ticket for the scan type's own event" do
      %{scope: scope, event: event, ticket: ticket} = setup_event()
      scan_type = scan_type_fixture(scope, event)

      assert {:ok, %{result: :accepted, subject: subject, label: "Ada Lovelace"}} =
               Scanning.scan(scope, scan_type, code(ticket))

      assert subject.id == ticket.id
    end

    test "rejects a ticket issued for a different event" do
      %{scope: scope, event: event, ticket: ticket} = setup_event()
      other_event = event_fixture(scope, %{"name" => "Another event"})
      scan_type = scan_type_fixture(scope, other_event)

      assert {:error, :wrong_event} = Scanning.scan(scope, scan_type, code(ticket))
    end

    test "rejects a code issued by another organisation" do
      %{scope: scope, event: event} = setup_event()
      %{ticket: other_ticket} = setup_event()

      scan_type = scan_type_fixture(scope, event)

      assert {:error, :not_found} = Scanning.scan(scope, scan_type, code(other_ticket))
      assert Scanning.list_recent_scans(scope) == []
    end

    test "raises when scanning at another organisation's scan type" do
      %{scope: scope_a, ticket: ticket} = setup_event()
      %{scope: scope_b, event: event_b} = setup_event()

      scan_type_b = scan_type_fixture(scope_b, event_b)

      assert_raise Ecto.NoResultsError, fn ->
        Scanning.scan(scope_a, scan_type_b, code(ticket))
      end
    end
  end

  describe "rule: once per attendee" do
    test "a second scan is a duplicate" do
      %{scope: scope, event: event, ticket: ticket} = setup_event()
      scan_type = scan_type_fixture(scope, event)

      assert {:ok, %{result: :accepted}} = Scanning.scan(scope, scan_type, code(ticket))

      assert {:ok, %{result: :duplicate, message: message}} =
               Scanning.scan(scope, scan_type, code(ticket))

      assert message =~ "Already claimed"
    end

    test "repeat scans are accepted when the rule is off" do
      %{scope: scope, event: event, ticket: ticket} = setup_event()

      scan_type =
        scan_type_fixture(scope, event, %{"rules" => %{"once_per_subject" => false}})

      assert {:ok, %{result: :accepted}} = Scanning.scan(scope, scan_type, code(ticket))
      assert {:ok, %{result: :accepted}} = Scanning.scan(scope, scan_type, code(ticket))
    end

    test "the same attendee can still claim a different checkpoint" do
      %{scope: scope, event: event, ticket: ticket} = setup_event()
      lunch = scan_type_fixture(scope, event, %{"name" => "Lunch"})
      merch = scan_type_fixture(scope, event, %{"name" => "Merch"})

      assert {:ok, %{result: :accepted}} = Scanning.scan(scope, lunch, code(ticket))
      assert {:ok, %{result: :accepted}} = Scanning.scan(scope, merch, code(ticket))
    end
  end

  describe "rule: active window" do
    test "a scan before the window opens is expired" do
      %{scope: scope, event: event, ticket: ticket} = setup_event()

      scan_type =
        scan_type_fixture(scope, event, %{
          "active_from" => DateTime.add(DateTime.utc_now(), 1, :hour)
        })

      assert {:ok, %{result: :expired, message: message}} =
               Scanning.scan(scope, scan_type, code(ticket))

      assert message =~ "opens at"
    end

    test "a scan after the window closes is expired" do
      %{scope: scope, event: event, ticket: ticket} = setup_event()

      scan_type =
        scan_type_fixture(scope, event, %{
          "active_to" => DateTime.add(DateTime.utc_now(), -1, :hour)
        })

      assert {:ok, %{result: :expired, message: message}} =
               Scanning.scan(scope, scan_type, code(ticket))

      assert message =~ "closed at"
    end

    test "a scan inside the window is accepted" do
      %{scope: scope, event: event, ticket: ticket} = setup_event()

      scan_type =
        scan_type_fixture(scope, event, %{
          "active_from" => DateTime.add(DateTime.utc_now(), -1, :hour),
          "active_to" => DateTime.add(DateTime.utc_now(), 1, :hour)
        })

      assert {:ok, %{result: :accepted}} = Scanning.scan(scope, scan_type, code(ticket))
    end

    test "a switched-off checkpoint denies every scan" do
      %{scope: scope, event: event, ticket: ticket} = setup_event()
      scan_type = scan_type_fixture(scope, event)
      {:ok, scan_type} = Scanning.set_active(scope, scan_type, false)

      assert {:ok, %{result: :denied, message: "This checkpoint is switched off"}} =
               Scanning.scan(scope, scan_type, code(ticket))
    end
  end

  describe "rule: requires prior scan" do
    test "requires_check_in denies an attendee who hasn't checked in" do
      %{scope: scope, event: event, ticket: ticket} = setup_event()
      scan_type = scan_type_fixture(scope, event, %{"rules" => %{"requires_check_in" => true}})

      assert {:ok, %{result: :denied, message: "Must be checked in to the event first"}} =
               Scanning.scan(scope, scan_type, code(ticket))
    end

    test "requires_check_in accepts an attendee who has checked in" do
      %{scope: scope, event: event, ticket: ticket} = setup_event()
      scan_type = scan_type_fixture(scope, event, %{"rules" => %{"requires_check_in" => true}})
      check_in(scope, event, ticket)

      assert {:ok, %{result: :accepted}} = Scanning.scan(scope, scan_type, code(ticket))
    end

    test "requires_prior_scan_type_id denies until the earlier checkpoint is claimed" do
      %{scope: scope, event: event, ticket: ticket} = setup_event()
      entry = scan_type_fixture(scope, event, %{"name" => "Entry"})

      lunch =
        scan_type_fixture(scope, event, %{
          "name" => "Lunch",
          "rules" => %{"requires_prior_scan_type_id" => entry.id}
        })

      assert {:ok, %{result: :denied, message: "Requires Entry first"}} =
               Scanning.scan(scope, lunch, code(ticket))

      assert {:ok, %{result: :accepted}} = Scanning.scan(scope, entry, code(ticket))
      assert {:ok, %{result: :accepted}} = Scanning.scan(scope, lunch, code(ticket))
    end

    test "a denied scan at the prior checkpoint doesn't satisfy the requirement" do
      %{scope: scope, event: event, ticket: ticket} = setup_event()
      entry = scan_type_fixture(scope, event, %{"name" => "Entry"})
      {:ok, entry} = Scanning.set_active(scope, entry, false)

      lunch =
        scan_type_fixture(scope, event, %{
          "name" => "Lunch",
          "rules" => %{"requires_prior_scan_type_id" => entry.id}
        })

      assert {:ok, %{result: :denied}} = Scanning.scan(scope, entry, code(ticket))

      assert {:ok, %{result: :denied, message: "Requires Entry first"}} =
               Scanning.scan(scope, lunch, code(ticket))
    end
  end

  describe "rule: allowed ticket types" do
    test "denies a ticket type that isn't on the list" do
      %{scope: scope, event: event, ticket: ticket} = setup_event()
      vip = ticket_type_fixture(scope, event, %{"name" => "VIP"})

      lounge =
        scan_type_fixture(scope, event, %{
          "name" => "VIP lounge",
          "rules" => %{"allowed_ticket_type_ids" => [vip.id]}
        })

      assert {:ok, %{result: :denied, message: message}} =
               Scanning.scan(scope, lounge, code(ticket))

      assert message =~ "Not valid for General tickets"
    end

    test "accepts a ticket type that is on the list" do
      %{scope: scope, event: event} = setup_event()
      vip = ticket_type_fixture(scope, event, %{"name" => "VIP"})
      vip_ticket = ticket_fixture(event, vip, %{"attendee_name" => "Grace Hopper"})

      lounge =
        scan_type_fixture(scope, event, %{
          "name" => "VIP lounge",
          "rules" => %{"allowed_ticket_type_ids" => [vip.id]}
        })

      assert {:ok, %{result: :accepted, label: "Grace Hopper"}} =
               Scanning.scan(scope, lounge, code(vip_ticket))
    end
  end

  describe "combined rules" do
    test "the most general failure wins: a closed window beats a ticket-type denial" do
      %{scope: scope, event: event, ticket: ticket} = setup_event()
      vip = ticket_type_fixture(scope, event, %{"name" => "VIP"})

      scan_type =
        scan_type_fixture(scope, event, %{
          "name" => "VIP lunch",
          "active_to" => DateTime.add(DateTime.utc_now(), -1, :hour),
          "rules" => %{"allowed_ticket_type_ids" => [vip.id]}
        })

      assert {:ok, %{result: :expired}} = Scanning.scan(scope, scan_type, code(ticket))
    end

    test "a ticket-type denial beats a duplicate" do
      %{scope: scope, event: event} = setup_event()
      vip = ticket_type_fixture(scope, event, %{"name" => "VIP"})
      vip_ticket = ticket_fixture(event, vip, %{"attendee_name" => "Grace Hopper"})

      scan_type =
        scan_type_fixture(scope, event, %{
          "name" => "VIP lunch",
          "rules" => %{"allowed_ticket_type_ids" => [vip.id]}
        })

      assert {:ok, %{result: :accepted}} = Scanning.scan(scope, scan_type, code(vip_ticket))
      assert {:ok, %{result: :duplicate}} = Scanning.scan(scope, scan_type, code(vip_ticket))

      {:ok, _} =
        Scanning.update_scan_type(scope, scan_type, %{
          "rules" => %{"allowed_ticket_type_ids" => []}
        })

      scan_type = Scanning.get_scan_type_for_scope!(scope, scan_type.id)
      assert {:ok, %{result: :duplicate}} = Scanning.scan(scope, scan_type, code(vip_ticket))
    end

    test "check-in plus once-per-attendee: accepted once, then duplicate" do
      %{scope: scope, event: event, ticket: ticket} = setup_event()

      scan_type =
        scan_type_fixture(scope, event, %{
          "rules" => %{"requires_check_in" => true, "once_per_subject" => true}
        })

      check_in(scope, event, ticket)

      assert {:ok, %{result: :accepted}} = Scanning.scan(scope, scan_type, code(ticket))
      assert {:ok, %{result: :duplicate}} = Scanning.scan(scope, scan_type, code(ticket))
    end
  end

  describe "scan logs, tallies and broadcasts" do
    test "every outcome is logged, including denials" do
      %{scope: scope, event: event, ticket: ticket} = setup_event()
      scan_type = scan_type_fixture(scope, event)

      {:ok, _} = Scanning.scan(scope, scan_type, code(ticket))
      {:ok, _} = Scanning.scan(scope, scan_type, code(ticket))

      assert [%ScanLog{result: "duplicate"}, %ScanLog{result: "accepted"}] =
               Scanning.list_recent_scans(scope)
    end

    test "list_recent_scans/2 is tenant scoped" do
      %{scope: scope_a, event: event_a, ticket: ticket_a} = setup_event()
      %{scope: scope_b, event: event_b, ticket: ticket_b} = setup_event()

      {:ok, _} = Scanning.scan(scope_a, scan_type_fixture(scope_a, event_a), code(ticket_a))
      {:ok, _} = Scanning.scan(scope_b, scan_type_fixture(scope_b, event_b), code(ticket_b))

      assert [%ScanLog{organization_id: org_id}] = Scanning.list_recent_scans(scope_a)
      assert org_id == scope_a.organization.id
    end

    test "tallies/2 counts accepted claims against the eligible attendees" do
      %{scope: scope, event: event, ticket: ticket, ticket_type: ticket_type} = setup_event()
      ticket_fixture(event, ticket_type, %{"attendee_name" => "Alan Turing"})
      scan_type = scan_type_fixture(scope, event)

      assert [%{claimed: 0, eligible: 2}] = Scanning.tallies(scope, [scan_type])

      {:ok, _} = Scanning.scan(scope, scan_type, code(ticket))
      {:ok, _} = Scanning.scan(scope, scan_type, code(ticket))

      assert [%{claimed: 1, eligible: 2}] = Scanning.tallies(scope, [scan_type])
    end

    test "tallies/2 narrows the denominator to the allowed ticket types" do
      %{scope: scope, event: event} = setup_event()
      vip = ticket_type_fixture(scope, event, %{"name" => "VIP"})
      ticket_fixture(event, vip, %{"attendee_name" => "Grace Hopper"})

      scan_type =
        scan_type_fixture(scope, event, %{"rules" => %{"allowed_ticket_type_ids" => [vip.id]}})

      assert [%{claimed: 0, eligible: 1}] = Scanning.tallies(scope, [scan_type])
    end

    test "scan/4 broadcasts the log to subscribers of the organisation" do
      %{scope: scope, event: event, ticket: ticket} = setup_event()
      scan_type = scan_type_fixture(scope, event)

      :ok = Scanning.subscribe(scope)
      {:ok, %{log: log}} = Scanning.scan(scope, scan_type, code(ticket))

      assert_receive {:scan_logged, %ScanLog{id: id, result: "accepted"}}
      assert id == log.id
    end
  end
end
