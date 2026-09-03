defmodule DatemWeb.AccessLive.VisitorsTest do
  use DatemWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Datem.AccountsFixtures
  import Datem.OrganizationsFixtures

  describe "access control" do
    test "operators can view the visitors page", %{conn: conn} do
      %{user: owner, organization: organization} = user_with_org_fixture()
      owner_scope = scope_fixture(owner, organization)

      operator = user_fixture()
      add_member_fixture(owner_scope, operator, :operator)

      {:ok, _lv, html} = conn |> log_in_user(operator) |> live(~p"/visitors")

      assert html =~ "Visitors"
    end

    test "viewers are redirected away", %{conn: conn} do
      %{user: owner, organization: organization} = user_with_org_fixture()
      owner_scope = scope_fixture(owner, organization)

      viewer = user_fixture()
      add_member_fixture(owner_scope, viewer, :viewer)

      assert {:error, {:redirect, %{to: "/"}}} =
               conn |> log_in_user(viewer) |> live(~p"/visitors")
    end
  end

  describe "registering a visitor" do
    test "registers a walk-in visitor and issues a pass", %{conn: conn} do
      %{user: owner} = user_with_org_fixture()

      {:ok, lv, _html} = conn |> log_in_user(owner) |> live(~p"/visitors")

      html =
        lv
        |> form("#visitor_form", visitor: %{"name" => "Jane Doe", "company" => "Acme"})
        |> render_submit()

      assert html =~ "Jane Doe"
      assert html =~ "registered"
    end
  end

  describe "tenant isolation" do
    test "an organisation cannot see another organisation's visitors", %{conn: conn} do
      %{user: user_a, organization: organization_a} = user_with_org_fixture()
      %{user: user_b, organization: organization_b} = user_with_org_fixture()
      scope_b = scope_fixture(user_b, organization_b)

      {:ok, visitor_b} = Datem.Access.register_visitor(scope_b, %{"name" => "Other Org Visitor"})

      {:ok, _lv, html} = conn |> log_in_user(user_a) |> live(~p"/visitors")

      refute html =~ "Other Org Visitor"
      assert visitor_b.organization_id != organization_a.id
    end
  end
end
