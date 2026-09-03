defmodule Datem.GS1Test do
  use Datem.DataCase, async: true

  alias Datem.GS1
  alias Datem.GS1.Identifier

  import Datem.OrganizationsFixtures

  describe "issue_identifier/4" do
    test "issues an interoperable identifier when the org has a GS1 prefix" do
      scope = owner_scope_fixture()

      {:ok, organization} =
        Datem.Organizations.update_organization(scope, %{"gs1_company_prefix" => "0614141"})

      scope = %{scope | organization: organization}

      assert {:ok, %Identifier{} = identifier} =
               GS1.issue_identifier(scope, :gsrn, "visitor", 1)

      assert identifier.interoperable
      assert identifier.kind == :gsrn
      assert identifier.ai == "8018"
      assert String.starts_with?(identifier.value, "0614141")
      assert identifier.digital_link == "https://id.datem.io/8018/#{identifier.value}"
    end

    test "falls back to a non-interoperable internal identifier without a GS1 prefix" do
      scope = owner_scope_fixture()

      assert {:ok, %Identifier{} = identifier} = GS1.issue_identifier(scope, :giai, "vehicle", 1)

      refute identifier.interoperable
    end

    test "round-trips build -> digital link -> resolve" do
      scope = owner_scope_fixture()

      {:ok, identifier} = GS1.issue_identifier(scope, :gsrn, "visitor", 42)

      assert {:ok, resolved} = GS1.resolve_digital_link(scope, identifier.digital_link)
      assert resolved.id == identifier.id
      assert resolved.subject_type == "visitor"
      assert resolved.subject_id == "42"
    end
  end

  describe "resolve_digital_link/2 tenant scoping" do
    test "rejects a digital link issued by a different organisation" do
      scope_a = owner_scope_fixture()
      scope_b = owner_scope_fixture()

      {:ok, identifier} = GS1.issue_identifier(scope_a, :gsrn, "visitor", 1)

      assert {:error, :not_found} = GS1.resolve_digital_link(scope_b, identifier.digital_link)
    end

    test "rejects an unresolvable / malformed digital link" do
      scope = owner_scope_fixture()

      assert {:error, :invalid_digital_link} = GS1.resolve_digital_link(scope, "not a link")
    end
  end
end
