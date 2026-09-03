defmodule DatemWeb.OrganizationLive.SettingsTest do
  use DatemWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Datem.AccountsFixtures
  import Datem.OrganizationsFixtures

  alias Datem.Organizations

  describe "access control" do
    test "owners can view the settings page", %{conn: conn} do
      user = user_fixture()
      user_with_org_fixture(%{user: user})

      {:ok, _lv, html} = conn |> log_in_user(user) |> live(~p"/organization/settings")

      assert html =~ "Organisation settings"
    end

    test "viewers are redirected away", %{conn: conn} do
      %{user: owner, organization: organization} = user_with_org_fixture()
      owner_scope = scope_fixture(owner, organization)

      viewer = user_fixture()
      add_member_fixture(owner_scope, viewer, :viewer)

      assert {:error, {:redirect, %{to: "/"}}} =
               conn |> log_in_user(viewer) |> live(~p"/organization/settings")
    end
  end

  describe "updating the GS1 company prefix" do
    test "accepts a valid prefix", %{conn: conn} do
      %{user: owner, organization: organization} = user_with_org_fixture()
      scope = scope_fixture(owner, organization)

      {:ok, lv, _html} = conn |> log_in_user(owner) |> live(~p"/organization/settings")

      html =
        lv
        |> form("#organization_form",
          organization: %{"name" => organization.name, "gs1_company_prefix" => "0614141"}
        )
        |> render_submit()

      assert html =~ "Organisation settings updated."
      assert html =~ "GS1-interoperable"

      assert Organizations.get_organization_for_scope!(scope, organization.id).gs1_company_prefix ==
               "0614141"
    end

    test "rejects a malformed prefix", %{conn: conn} do
      %{user: owner, organization: organization} = user_with_org_fixture(%{})

      {:ok, lv, _html} = conn |> log_in_user(owner) |> live(~p"/organization/settings")

      html =
        lv
        |> form("#organization_form",
          organization: %{"name" => organization.name, "gs1_company_prefix" => "abc"}
        )
        |> render_submit()

      assert html =~ "must be 6 to 10 digits"
    end
  end
end
