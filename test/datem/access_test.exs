defmodule Datem.AccessTest do
  use Datem.DataCase, async: true

  alias Datem.Access
  alias Datem.Access.{Site, AccessPoint, Visitor, VisitorPass, Vehicle}

  import Datem.OrganizationsFixtures

  defp site_fixture(scope, attrs \\ %{}) do
    {:ok, site} = Access.create_site(scope, Enum.into(attrs, %{"name" => "Head office"}))
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

  defp visitor_fixture(scope, attrs \\ %{}) do
    {:ok, visitor} = Access.register_visitor(scope, Enum.into(attrs, %{"name" => "Jane Doe"}))
    visitor
  end

  describe "sites" do
    test "create_site/2 issues a GLN alongside the record" do
      scope = owner_scope_fixture()

      assert {:ok, %Site{} = site} =
               Access.create_site(scope, %{"name" => "Head office", "address" => "1 Main St"})

      assert site.gln
      assert site.organization_id == scope.organization.id
    end

    test "list_sites/1 only returns the caller's organisation" do
      scope_a = owner_scope_fixture()
      scope_b = owner_scope_fixture()

      site_a = site_fixture(scope_a)
      _site_b = site_fixture(scope_b)

      assert [%Site{id: id}] = Access.list_sites(scope_a)
      assert id == site_a.id
    end

    test "get_site_for_scope!/2 raises for a site belonging to another organisation" do
      scope_a = owner_scope_fixture()
      scope_b = owner_scope_fixture()

      site_b = site_fixture(scope_b)

      assert_raise Ecto.NoResultsError, fn -> Access.get_site_for_scope!(scope_a, site_b.id) end
    end
  end

  describe "access points" do
    test "create_access_point/2 issues a GLN extension" do
      scope = owner_scope_fixture()
      site = site_fixture(scope)

      assert {:ok, %AccessPoint{} = access_point} =
               Access.create_access_point(scope, %{"name" => "Main gate", "site_id" => site.id})

      assert access_point.gln
    end

    test "list_access_points/1 is tenant scoped" do
      scope_a = owner_scope_fixture()
      scope_b = owner_scope_fixture()

      site_a = site_fixture(scope_a)
      site_b = site_fixture(scope_b)
      access_point_a = access_point_fixture(scope_a, site_a)
      access_point_fixture(scope_b, site_b)

      assert [%AccessPoint{id: id}] = Access.list_access_points(scope_a)
      assert id == access_point_a.id
    end
  end

  describe "visitors and passes" do
    test "issue_pass/3 issues a GSRN and marks the visitor registered" do
      scope = owner_scope_fixture()
      visitor = visitor_fixture(scope)

      assert {:ok, %{pass: %VisitorPass{} = pass, visitor: visitor}} =
               Access.issue_pass(scope, visitor)

      assert visitor.status == "registered"
      assert pass.gs1_identifier.kind == :gsrn
      assert DateTime.compare(pass.valid_to, pass.valid_from) == :gt
    end

    test "issue_pass/3 raises when the visitor belongs to another organisation" do
      scope_a = owner_scope_fixture()
      scope_b = owner_scope_fixture()

      visitor_b = visitor_fixture(scope_b)

      assert_raise Ecto.NoResultsError, fn -> Access.issue_pass(scope_a, visitor_b) end
    end

    test "list_visitors/1 is tenant scoped" do
      scope_a = owner_scope_fixture()
      scope_b = owner_scope_fixture()

      visitor_a = visitor_fixture(scope_a)
      visitor_fixture(scope_b)

      assert [%Visitor{id: id}] = Access.list_visitors(scope_a)
      assert id == visitor_a.id
    end
  end

  describe "pre-registration" do
    test "create_pre_registration/2 then complete_pre_registration/2 issues a pass" do
      scope = owner_scope_fixture()

      assert {:ok, visitor} = Access.create_pre_registration(scope, "Alex Host")
      assert visitor.status == "pending"
      assert visitor.invite_token

      pending = Access.get_pending_pre_registration_by_token(visitor.invite_token)
      assert pending.id == visitor.id

      assert {:ok, %{visitor: completed, pass: pass}} =
               Access.complete_pre_registration(pending, %{
                 "name" => "Jane Doe",
                 "contact" => "jane@example.com"
               })

      assert completed.status == "registered"
      assert pass.gs1_identifier.kind == :gsrn
    end

    test "get_pending_pre_registration_by_token/1 returns nil once completed" do
      scope = owner_scope_fixture()
      {:ok, visitor} = Access.create_pre_registration(scope, "Alex Host")

      pending = Access.get_pending_pre_registration_by_token(visitor.invite_token)

      {:ok, _} =
        Access.complete_pre_registration(pending, %{
          "name" => "Jane Doe",
          "contact" => "jane@example.com"
        })

      refute Access.get_pending_pre_registration_by_token(visitor.invite_token)
    end

    test "an unknown token resolves to nil" do
      refute Access.get_pending_pre_registration_by_token("does-not-exist")
    end
  end

  describe "vehicles" do
    test "register_vehicle/2 issues a GIAI" do
      scope = owner_scope_fixture()

      assert {:ok, %Vehicle{} = vehicle} =
               Access.register_vehicle(scope, %{"plate" => "kaa 123a"})

      assert vehicle.plate == "KAA 123A"
      assert vehicle.gs1_identifier.kind == :giai
    end

    test "list_vehicles/1 is tenant scoped" do
      scope_a = owner_scope_fixture()
      scope_b = owner_scope_fixture()

      {:ok, vehicle_a} = Access.register_vehicle(scope_a, %{"plate" => "AAA 111"})
      {:ok, _vehicle_b} = Access.register_vehicle(scope_b, %{"plate" => "BBB 222"})

      assert [%Vehicle{id: id}] = Access.list_vehicles(scope_a)
      assert id == vehicle_a.id
    end
  end

  describe "access logs" do
    test "record_scan/5 enforces alternating direction" do
      scope = owner_scope_fixture()
      site = site_fixture(scope)
      access_point = access_point_fixture(scope, site)
      visitor = visitor_fixture(scope)
      {:ok, %{pass: pass}} = Access.issue_pass(scope, visitor)

      assert {:ok, _log} = Access.record_scan(scope, access_point, pass, "in")
      assert {:error, :already_inside} = Access.record_scan(scope, access_point, pass, "in")
      assert {:ok, _log} = Access.record_scan(scope, access_point, pass, "out")
      assert {:error, :not_inside} = Access.record_scan(scope, access_point, pass, "out")
    end

    test "record_scan/5 raises for an access point belonging to another organisation" do
      scope_a = owner_scope_fixture()
      scope_b = owner_scope_fixture()

      site_b = site_fixture(scope_b)
      access_point_b = access_point_fixture(scope_b, site_b)
      visitor_a = visitor_fixture(scope_a)
      {:ok, %{pass: pass}} = Access.issue_pass(scope_a, visitor_a)

      assert_raise Ecto.NoResultsError, fn ->
        Access.record_scan(scope_a, access_point_b, pass, "in")
      end
    end

    test "record_scan/5 rejects an expired pass" do
      scope = owner_scope_fixture()
      site = site_fixture(scope)
      access_point = access_point_fixture(scope, site)
      visitor = visitor_fixture(scope)

      {:ok, %{pass: pass}} =
        Access.issue_pass(scope, visitor, %{
          valid_from: DateTime.add(DateTime.utc_now(), -2, :hour) |> DateTime.truncate(:second),
          valid_to: DateTime.add(DateTime.utc_now(), -1, :hour) |> DateTime.truncate(:second)
        })

      assert {:error, :expired} = Access.record_scan(scope, access_point, pass, "in")
    end

    test "record_scan/5 rejects a revoked pass" do
      scope = owner_scope_fixture()
      site = site_fixture(scope)
      access_point = access_point_fixture(scope, site)
      visitor = visitor_fixture(scope)
      {:ok, %{pass: pass}} = Access.issue_pass(scope, visitor)
      {:ok, pass} = Access.revoke_pass(scope, pass)

      assert {:error, :revoked} = Access.record_scan(scope, access_point, pass, "in")
    end
  end

  describe "scan/4 and resolve_scan_subject/2" do
    test "scan/4 resolves a visitor's Digital Link QR and checks them in" do
      scope = owner_scope_fixture()
      site = site_fixture(scope)
      access_point = access_point_fixture(scope, site)
      visitor = visitor_fixture(scope)
      {:ok, %{pass: pass}} = Access.issue_pass(scope, visitor)

      assert {:ok, _log, entity, "in"} =
               Access.scan(scope, access_point, pass.gs1_identifier.digital_link)

      assert entity.id == visitor.id
    end

    test "scan/4 alternates direction across repeated scans" do
      scope = owner_scope_fixture()
      site = site_fixture(scope)
      access_point = access_point_fixture(scope, site)
      visitor = visitor_fixture(scope)
      {:ok, %{pass: pass}} = Access.issue_pass(scope, visitor)
      code = pass.gs1_identifier.digital_link

      assert {:ok, _log, _entity, "in"} = Access.scan(scope, access_point, code)
      assert {:ok, _log, _entity, "out"} = Access.scan(scope, access_point, code)
    end

    test "resolve_scan_subject/2 rejects a code issued by another organisation" do
      scope_a = owner_scope_fixture()
      scope_b = owner_scope_fixture()

      visitor_b = visitor_fixture(scope_b)
      {:ok, %{pass: pass}} = Access.issue_pass(scope_b, visitor_b)

      assert {:error, :not_found} =
               Access.resolve_scan_subject(scope_a, pass.gs1_identifier.digital_link)
    end

    test "resolve_scan_subject/2 returns :not_found for an unrecognised code" do
      scope = owner_scope_fixture()

      assert {:error, _reason} =
               Access.resolve_scan_subject(scope, "https://id.datem.io/8018/000000000000000000")
    end
  end

  describe "list_onsite/1" do
    test "returns only subjects whose last scan was an entry" do
      scope = owner_scope_fixture()
      site = site_fixture(scope)
      access_point = access_point_fixture(scope, site)

      visitor_in = visitor_fixture(scope, %{"name" => "Inside Person"})
      {:ok, %{pass: pass_in}} = Access.issue_pass(scope, visitor_in)
      Access.record_scan(scope, access_point, pass_in, "in")

      visitor_out = visitor_fixture(scope, %{"name" => "Left Person"})
      {:ok, %{pass: pass_out}} = Access.issue_pass(scope, visitor_out)
      Access.record_scan(scope, access_point, pass_out, "in")
      Access.record_scan(scope, access_point, pass_out, "out")

      assert [%{name: "Inside Person"}] = Access.list_onsite(scope)
    end
  end
end
