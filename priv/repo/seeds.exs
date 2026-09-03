# Demo/seed data for Datem.
#
#     mix run priv/repo/seeds.exs      # (also run automatically by `mix ecto.setup`)
#     mix run priv/repo/demo.exs       # scripted end-to-end demo on top of this data
#
# Seeding is idempotent at the organisation level: if the demo organisation
# already exists the script exits without touching anything, so you can run
# `mix ecto.setup` repeatedly. Use `mix ecto.reset` to start from scratch.

import Ecto.Query, warn: false

alias Datem.Accounts
alias Datem.Accounts.{Scope, User}
alias Datem.{Access, Organizations, Repo, Scanning, Ticketing}

password = "datem-demo-password"

log = fn message -> IO.puts("  " <> message) end

# A user that can log in straight away: registration only captures the email
# (magic-link first), so the demo sets a password and confirms the account.
create_user = fn email ->
  case Accounts.get_user_by_email(email) do
    %User{} = user ->
      user

    nil ->
      {:ok, user} = Accounts.register_user(%{email: email})

      user
      |> User.confirm_changeset()
      |> Repo.update!()
      |> User.password_changeset(%{password: password})
      |> Repo.update!()
  end
end

now = DateTime.utc_now() |> DateTime.truncate(:second)
today = DateTime.to_date(now)

at = fn date, hour ->
  DateTime.new!(date, Time.new!(hour, 0, 0), "Etc/UTC")
end

if Repo.exists?(
     from(o in Datem.Organizations.Organization, where: o.slug == "acme-manufacturing")
   ) do
  IO.puts("""
  Demo data already present — skipping seeds.
  Run `mix ecto.reset` to rebuild the database from scratch.
  """)
else
  IO.puts("\nSeeding Datem demo data…\n")

  ## ---------------------------------------------------------------------
  ## Organisation 1 — Acme Manufacturing (has a licensed GS1 Company Prefix)
  ## ---------------------------------------------------------------------

  owner = create_user.("owner@datem.test")

  {:ok, %{organization: acme, membership: owner_membership}} =
    Organizations.create_organization_with_owner(owner, "Acme Manufacturing")

  acme_scope = Scope.for_user(owner) |> Scope.put_organization(acme, owner_membership)

  # A licensed prefix makes every identifier GS1-interoperable. Organisations
  # without one still get Digital-Link-shaped internal identifiers — see the
  # second organisation below.
  {:ok, acme} =
    Organizations.update_organization(acme_scope, %{"gs1_company_prefix" => "0952123"})

  acme_scope = Scope.put_organization(acme_scope, acme, owner_membership)

  log.("organisation: #{acme.name} (prefix #{acme.gs1_company_prefix})")

  for {email, role} <- [
        {"admin@datem.test", :admin},
        {"operator@datem.test", :operator},
        {"viewer@datem.test", :viewer}
      ] do
    user = create_user.(email)
    {:ok, _membership} = Organizations.add_member(acme_scope, user, role)
    log.("member: #{email} (#{role})")
  end

  operator = Accounts.get_user_by_email("operator@datem.test")

  ## Sites and access points

  {:ok, hq} =
    Access.create_site(acme_scope, %{
      "name" => "Acme HQ",
      "address" => "12 Enterprise Road, Nairobi",
      "capacity" => 250
    })

  {:ok, plant} =
    Access.create_site(acme_scope, %{
      "name" => "Acme Plant 2",
      "address" => "Mombasa Road, Athi River",
      "capacity" => 400
    })

  log.("sites: #{hq.name} (GLN #{hq.gln}), #{plant.name} (GLN #{plant.gln})")

  {:ok, main_gate} =
    Access.create_access_point(acme_scope, %{"name" => "Main Gate", "site_id" => hq.id})

  {:ok, _reception} =
    Access.create_access_point(acme_scope, %{"name" => "Reception", "site_id" => hq.id})

  {:ok, _plant_gate} =
    Access.create_access_point(acme_scope, %{"name" => "Plant Gate", "site_id" => plant.id})

  log.("access points: Main Gate (GLN #{main_gate.gln}), Reception, Plant Gate")

  ## Visitors and passes

  visitors = [
    %{
      "name" => "Amina Yusuf",
      "company" => "Kite Logistics",
      "host" => "Jane Owner",
      "contact" => "amina@kitelogistics.test"
    },
    %{
      "name" => "Brian Otieno",
      "company" => "Otieno & Co",
      "host" => "Sam Admin",
      "contact" => "brian@otieno.test"
    },
    %{
      "name" => "Chloe Mwangi",
      "company" => "Northwind Events",
      "host" => "Jane Owner",
      "contact" => "chloe@northwind.test"
    }
  ]

  passes =
    for attrs <- visitors do
      {:ok, visitor} = Access.register_visitor(acme_scope, attrs)
      {:ok, %{pass: pass}} = Access.issue_pass(acme_scope, visitor)
      log.("visitor pass: #{visitor.name} → #{pass.gs1_identifier.digital_link}")
      {visitor, pass}
    end

  # Amina is already on site, so the on-site view and dashboard aren't empty.
  [{_amina, amina_pass} | _] = passes
  {:ok, _log} = Access.record_scan(acme_scope, main_gate, amina_pass, "in", operator)

  ## A vehicle with a GIAI windscreen tag

  {:ok, vehicle} =
    Access.register_vehicle(acme_scope, %{
      "plate" => "KDA 123X",
      "make" => "Toyota",
      "model" => "Hilux"
    })

  log.("vehicle: #{vehicle.plate} → #{vehicle.gs1_identifier.digital_link}")

  ## Event, ticket types and attendees

  {:ok, summit} =
    Ticketing.create_event(acme_scope, %{
      "name" => "Acme Supplier Summit",
      "description" => "Annual supplier day: keynote, workshops and lunch.",
      "venue" => "Acme HQ",
      "starts_at" => at.(today, 8),
      "ends_at" => at.(today, 18)
    })

  {:ok, summit} = Ticketing.create_join_link(acme_scope, summit)

  {:ok, general} =
    Ticketing.create_ticket_type(acme_scope, summit, %{
      "name" => "General",
      "price" => 0,
      "quantity" => 300
    })

  {:ok, vip} =
    Ticketing.create_ticket_type(acme_scope, summit, %{
      "name" => "VIP",
      "price" => 0,
      "quantity" => 40
    })

  log.("event: #{summit.name} — join link /join/#{summit.join_link_token}")

  attendees = [
    {"Dora Kimani", "dora@supplier.test", general},
    {"Eli Wanjiru", "eli@supplier.test", general},
    {"Faith Njoroge", "faith@supplier.test", general},
    {"Gitau Mburu", "gitau@supplier.test", vip}
  ]

  tickets =
    for {name, email, ticket_type} <- attendees do
      {:ok, ticket} =
        Ticketing.register_attendee(summit, ticket_type, %{
          "attendee_name" => name,
          "attendee_email" => email
        })

      ticket
    end

  log.(
    "tickets issued: #{length(tickets)} (#{Enum.count(attendees, &(elem(&1, 2).id == vip.id))} VIP)"
  )

  ## Checkpoints (scan types)

  {:ok, entry} =
    Scanning.create_scan_type(acme_scope, %{
      "name" => "Summit Entry",
      "event_id" => summit.id,
      "rules" => %{"once_per_subject" => false}
    })

  {:ok, _lunch} =
    Scanning.create_scan_type(acme_scope, %{
      "name" => "Lunch",
      "event_id" => summit.id,
      "active_from" => at.(today, 12),
      "active_to" => at.(today, 14),
      "rules" => %{
        "once_per_subject" => true,
        "requires_check_in" => true,
        "requires_prior_scan_type_id" => entry.id
      }
    })

  {:ok, _vip_lounge} =
    Scanning.create_scan_type(acme_scope, %{
      "name" => "VIP Lounge",
      "event_id" => summit.id,
      "rules" => %{
        "once_per_subject" => false,
        "requires_check_in" => true,
        "allowed_ticket_type_ids" => [vip.id]
      }
    })

  {:ok, _site_entry} =
    Scanning.create_scan_type(acme_scope, %{
      "name" => "HQ Turnstile",
      "site_id" => hq.id,
      "rules" => %{"once_per_subject" => false}
    })

  log.("checkpoints: Summit Entry, Lunch (12:00–14:00 UTC), VIP Lounge (VIP only), HQ Turnstile")

  # Check a couple of attendees in so the event dashboard has live numbers.
  for ticket <- Enum.take(tickets, 2) do
    digital_link = Repo.preload(ticket, :gs1_identifier).gs1_identifier.digital_link
    {:ok, _log, _ticket, _direction} = Ticketing.scan(acme_scope, summit, digital_link, operator)
    {:ok, _result} = Scanning.scan(acme_scope, entry, digital_link, operator)
  end

  ## ---------------------------------------------------------------------
  ## Organisation 2 — no GS1 prefix, used to demonstrate tenant isolation
  ## and the non-interoperable internal identifier fallback.
  ## ---------------------------------------------------------------------

  other_owner = create_user.("northwind@datem.test")

  {:ok, %{organization: northwind, membership: northwind_membership}} =
    Organizations.create_organization_with_owner(other_owner, "Northwind Events")

  northwind_scope =
    Scope.for_user(other_owner) |> Scope.put_organization(northwind, northwind_membership)

  {:ok, northwind_site} =
    Access.create_site(northwind_scope, %{"name" => "Northwind Arena", "capacity" => 1_000})

  {:ok, northwind_visitor} =
    Access.register_visitor(northwind_scope, %{"name" => "Zoe Achieng", "host" => "Northwind"})

  {:ok, %{pass: northwind_pass}} = Access.issue_pass(northwind_scope, northwind_visitor)

  log.(
    "organisation: #{northwind.name} (no GS1 prefix — internal, non-interoperable identifiers)"
  )

  log.("  #{northwind_site.name} GLN #{northwind_site.gln}")
  log.("  #{northwind_visitor.name} pass #{northwind_pass.gs1_identifier.digital_link}")

  IO.puts("""

  Done. Log in at http://localhost:4000/users/log-in with any of:

    owner@datem.test     (owner)
    admin@datem.test     (admin)
    operator@datem.test  (operator — can scan, cannot configure or export)
    viewer@datem.test    (viewer)
    northwind@datem.test (owner of a second organisation)

  Password for all of them: #{password}

  Next: run the scripted end-to-end demo with

    mix run priv/repo/demo.exs
  """)
end
