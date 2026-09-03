defmodule Datem.ReportingTest do
  use Datem.DataCase, async: true

  alias Datem.Access
  alias Datem.Reporting
  alias Datem.Reporting.{CSV, Export}
  alias Datem.Scanning
  alias Datem.Ticketing

  import Datem.OrganizationsFixtures

  setup do
    File.rm_rf!(Reporting.exports_dir())
    :ok
  end

  defp site_fixture(scope, attrs \\ %{}) do
    {:ok, site} = Access.create_site(scope, Enum.into(attrs, %{"name" => "HQ"}))
    site
  end

  defp access_point_fixture(scope, site, attrs \\ %{}) do
    {:ok, access_point} =
      Access.create_access_point(
        scope,
        Enum.into(attrs, %{"name" => "Main gate", "site_id" => site.id})
      )

    access_point
  end

  defp visitor_with_pass(scope, name) do
    {:ok, visitor} = Access.register_visitor(scope, %{"name" => name, "host" => "Grace"})
    {:ok, %{pass: pass}} = Access.issue_pass(scope, visitor)
    {visitor, pass}
  end

  defp event_fixture(scope, attrs \\ %{}) do
    {:ok, event} = Ticketing.create_event(scope, Enum.into(attrs, %{"name" => "Conference"}))
    Ticketing.get_event_for_scope!(scope, event.id) |> Repo.preload(:organization)
  end

  defp ticket_fixture(scope, event, attrs \\ %{}) do
    {:ok, ticket_type} =
      Ticketing.create_ticket_type(scope, event, %{"name" => attrs[:ticket_type] || "General"})

    {:ok, ticket} =
      Ticketing.register_attendee(event, ticket_type, %{
        "attendee_name" => attrs[:name] || "Ada Lovelace",
        "attendee_email" => attrs[:email] || "ada@example.com"
      })

    {ticket_type, ticket}
  end

  defp setup_access do
    scope = owner_scope_fixture()
    site = site_fixture(scope)
    access_point = access_point_fixture(scope, site)
    {visitor, pass} = visitor_with_pass(scope, "Ada Lovelace")

    %{scope: scope, site: site, access_point: access_point, visitor: visitor, pass: pass}
  end

  describe "dashboard/2" do
    test "counts who is on-site and who came in today" do
      %{scope: scope, access_point: ap, pass: pass} = setup_access()

      {:ok, _log} = Access.record_scan(scope, ap, pass, "in")

      dashboard = Reporting.dashboard(scope)

      assert dashboard.onsite_count == 1
      assert dashboard.visitors_today == 1
      assert [%{name: "Ada Lovelace"}] = dashboard.onsite
    end

    test "a subject that has scanned back out is no longer on-site but still counted today" do
      %{scope: scope, access_point: ap, pass: pass} = setup_access()

      {:ok, _} = Access.record_scan(scope, ap, pass, "in")
      {:ok, _} = Access.record_scan(scope, ap, pass, "out")

      dashboard = Reporting.dashboard(scope)

      assert dashboard.onsite_count == 0
      assert dashboard.visitors_today == 1
    end

    test "lists running events with their check-in counts" do
      scope = owner_scope_fixture()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      event =
        event_fixture(scope, %{
          "name" => "Running now",
          "starts_at" => DateTime.add(now, -1, :hour),
          "ends_at" => DateTime.add(now, 1, :hour)
        })

      event_fixture(scope, %{
        "name" => "Next month",
        "starts_at" => DateTime.add(now, 30, :day),
        "ends_at" => DateTime.add(now, 31, :day)
      })

      {_type, ticket} = ticket_fixture(scope, event)

      {:ok, _log, _ticket, "in"} =
        Ticketing.scan(scope, event, ticket.gs1_identifier.digital_link)

      assert [%{event: %{name: "Running now"}, registered: 1, checked_in: 1}] =
               Reporting.dashboard(scope).active_events
    end

    test "surfaces the most recent denials" do
      scope = owner_scope_fixture()
      event = event_fixture(scope)
      {_type, ticket} = ticket_fixture(scope, event)

      {:ok, scan_type} =
        Scanning.create_scan_type(scope, %{
          "name" => "Lunch",
          "event_id" => event.id,
          "rules" => %{"requires_check_in" => true}
        })

      {:ok, %{result: :denied}} =
        Scanning.scan(scope, scan_type, ticket.gs1_identifier.digital_link)

      assert [%{result: "denied", scan_type: %{name: "Lunch"}}] =
               Reporting.dashboard(scope).recent_denials
    end

    test "never reports another organisation's activity" do
      %{scope: scope, access_point: ap, pass: pass} = setup_access()
      {:ok, _} = Access.record_scan(scope, ap, pass, "in")

      other = owner_scope_fixture()
      dashboard = Reporting.dashboard(other)

      assert dashboard.onsite_count == 0
      assert dashboard.visitors_today == 0
      assert dashboard.recent_denials == []
    end
  end

  describe "access_report/2" do
    test "totals entries, exits and unique subjects, split by site and access point" do
      %{scope: scope, access_point: ap, pass: pass, site: site} = setup_access()
      {_visitor, other_pass} = visitor_with_pass(scope, "Grace Hopper")

      {:ok, _} = Access.record_scan(scope, ap, pass, "in")
      {:ok, _} = Access.record_scan(scope, ap, pass, "out")
      {:ok, _} = Access.record_scan(scope, ap, other_pass, "in")

      report = Reporting.access_report(scope)

      assert report.totals == %{entries: 2, exits: 1, unique_subjects: 2}
      assert [%{name: "HQ", entries: 2, exits: 1, site_id: site_id}] = report.by_site
      assert site_id == site.id

      assert [%{name: "Main gate", site_name: "HQ", entries: 2, exits: 1}] =
               report.by_access_point

      assert [%{entries: 2, exits: 1}] = report.by_day
    end

    test "filters by access point" do
      %{scope: scope, site: site, access_point: ap, pass: pass} = setup_access()
      side_gate = access_point_fixture(scope, site, %{"name" => "Side gate"})

      {:ok, _} = Access.record_scan(scope, ap, pass, "in")
      {:ok, _} = Access.record_scan(scope, side_gate, pass, "out")

      report = Reporting.access_report(scope, %{"access_point_id" => side_gate.id})

      assert report.totals.entries == 0
      assert report.totals.exits == 1
    end

    test "a date range excludes scans outside it" do
      %{scope: scope, access_point: ap, pass: pass} = setup_access()
      {:ok, _} = Access.record_scan(scope, ap, pass, "in")

      yesterday = Date.utc_today() |> Date.add(-1) |> Date.to_iso8601()
      report = Reporting.access_report(scope, %{"from" => yesterday, "to" => yesterday})

      assert report.totals.entries == 0
    end

    test "is scoped to the caller's organisation" do
      %{scope: scope, access_point: ap, pass: pass} = setup_access()
      {:ok, _} = Access.record_scan(scope, ap, pass, "in")

      assert Reporting.access_report(owner_scope_fixture()).totals.entries == 0
    end
  end

  describe "event_report/2" do
    test "reports attendance, rate, ticket types and checkpoint tallies" do
      scope = owner_scope_fixture()
      event = event_fixture(scope)
      {_type, ticket} = ticket_fixture(scope, event)
      {_vip_type, _vip_ticket} = ticket_fixture(scope, event, ticket_type: "VIP", name: "Grace")

      {:ok, _log, _ticket, "in"} =
        Ticketing.scan(scope, event, ticket.gs1_identifier.digital_link)

      {:ok, scan_type} =
        Scanning.create_scan_type(scope, %{"name" => "Lunch", "event_id" => event.id})

      {:ok, %{result: :accepted}} =
        Scanning.scan(scope, scan_type, ticket.gs1_identifier.digital_link)

      report = Reporting.event_report(scope, event)

      assert report.registered == 2
      assert report.checked_in == 1
      assert report.check_in_rate == 50

      assert [%{name: "General", checked_in: 1}, %{name: "VIP", checked_in: 0}] =
               report.by_ticket_type

      assert [%{scan_type: %{name: "Lunch"}, claimed: 1, eligible: 2}] = report.scan_types
    end
  end

  describe "exports" do
    test "an access-log export runs and writes a downloadable CSV" do
      %{scope: scope, access_point: ap, pass: pass} = setup_access()
      {:ok, _} = Access.record_scan(scope, ap, pass, "in")

      {:ok, export} = Reporting.request_export(scope, "access_logs", %{})

      # Oban runs inline in tests, so the job has already finished.
      export = Reporting.get_export_for_scope!(scope, export.id)

      assert export.status == "completed"
      assert export.row_count == 1

      csv = File.read!(Reporting.export_path(export))
      assert csv =~ "scanned_at,direction,subject_type,subject,site,access_point,operator"
      assert csv =~ "Ada Lovelace"
      assert csv =~ "Main gate"
    end

    test "an attendee export lists the event's tickets" do
      scope = owner_scope_fixture()
      event = event_fixture(scope)
      {_type, _ticket} = ticket_fixture(scope, event)

      {:ok, export} = Reporting.request_export(scope, "attendees", %{"event_id" => event.id})
      export = Reporting.get_export_for_scope!(scope, export.id)

      assert export.status == "completed"
      csv = File.read!(Reporting.export_path(export))
      assert csv =~ "Ada Lovelace,ada@example.com,General,registered"
    end

    test "a scan-tally export reports claimed vs eligible" do
      scope = owner_scope_fixture()
      event = event_fixture(scope)
      {_type, ticket} = ticket_fixture(scope, event)

      {:ok, scan_type} =
        Scanning.create_scan_type(scope, %{"name" => "Lunch", "event_id" => event.id})

      {:ok, %{result: :accepted}} =
        Scanning.scan(scope, scan_type, ticket.gs1_identifier.digital_link)

      {:ok, export} = Reporting.request_export(scope, "scan_tallies", %{"event_id" => event.id})
      export = Reporting.get_export_for_scope!(scope, export.id)

      assert File.read!(Reporting.export_path(export)) =~ "Lunch,Conference,1,1"
    end

    test "an export is only visible to the organisation that requested it" do
      %{scope: scope} = setup_access()
      {:ok, export} = Reporting.request_export(scope, "access_logs", %{})

      other = owner_scope_fixture()

      assert Reporting.list_exports(other) == []

      assert_raise Ecto.NoResultsError, fn ->
        Reporting.get_export_for_scope!(other, export.id)
      end
    end

    test "an export for an unknown event fails loudly and records why" do
      scope = owner_scope_fixture()

      assert_raise Ecto.NoResultsError, fn ->
        Reporting.request_export(scope, "attendees", %{"event_id" => 0})
      end

      assert [%Export{status: "failed", error: error}] = Reporting.list_exports(scope)
      assert error =~ "expected at least one result"
    end
  end

  describe "parse_filters/1" do
    test "widens dates to cover the whole day and ignores junk" do
      filters = Reporting.parse_filters(%{"from" => "2026-09-01", "to" => "2026-09-03"})

      assert filters.from == ~U[2026-09-01 00:00:00Z]
      assert filters.to == ~U[2026-09-03 23:59:59Z]

      assert Reporting.parse_filters(%{"from" => "not a date", "site_id" => ""}).from == nil
      assert Reporting.parse_filters(%{"site_id" => "7"}).site_id == 7
    end
  end

  describe "CSV.encode/2" do
    test "quotes fields containing separators, quotes and newlines" do
      csv = CSV.encode(["a", "b"], [["plain", ~s(with "quotes", commas)], [nil, "line\nbreak"]])

      assert csv ==
               "a,b\r\nplain,\"with \"\"quotes\"\", commas\"\r\n,\"line\nbreak\"\r\n"
    end
  end
end
