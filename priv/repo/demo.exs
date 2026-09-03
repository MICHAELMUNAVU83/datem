# Scripted end-to-end Datem demo.
#
#     mix run priv/repo/seeds.exs     # once, to create the demo organisation
#     mix run priv/repo/demo.exs
#
# Walks the full happy path plus the interesting denials, printing each step:
#
#   visitor:  register → issue GSRN pass QR → scan in → scan out
#   attendee: register on the join link → issue ticket QR → check in
#             → lunch scan (window closed → denied, then accepted)
#             → second lunch scan (duplicate) → check out
#
# Everything runs through the same public context functions the LiveViews
# call, so a green run means the real flow works, not just the database.

import Ecto.Query, warn: false

alias Datem.Accounts
alias Datem.Accounts.Scope
alias Datem.{Access, Organizations, Repo, Scanning, Ticketing}

defmodule DemoScript do
  @moduledoc false

  def heading(text) do
    IO.puts(
      "\n\e[1;34m── #{text} " <>
        String.duplicate("─", max(0, 60 - String.length(text))) <> "\e[0m"
    )
  end

  def step(text), do: IO.puts("  • #{text}")

  def accepted(text), do: IO.puts("  \e[32m✓ #{text}\e[0m")

  def denied(text), do: IO.puts("  \e[31m✗ #{text}\e[0m")

  def halt(text) do
    IO.puts("\n\e[31m#{text}\e[0m\n")
    System.halt(1)
  end
end

import DemoScript

## ---------------------------------------------------------------------
## Set up the caller: the demo organisation's owner, with an operator to
## attribute scans to (in the app this is whoever is logged into the
## scanning view).
## ---------------------------------------------------------------------

owner =
  Accounts.get_user_by_email("owner@datem.test") ||
    halt("No demo data found. Run `mix run priv/repo/seeds.exs` first.")

[membership | _] = Organizations.list_memberships_for_user(owner)
scope = Scope.for_user(owner) |> Scope.put_organization(membership.organization, membership)
operator = Accounts.get_user_by_email("operator@datem.test")

heading("Organisation")

step(
  "#{membership.organization.name} — GS1 company prefix #{membership.organization.gs1_company_prefix || "(none: internal identifiers)"}"
)

step("acting as #{owner.email} (#{membership.role}), scans attributed to #{operator.email}")

## ---------------------------------------------------------------------
## 1. Visitor access: register → issue QR → scan in → scan out
## ---------------------------------------------------------------------

heading("1. Visitor access")

main_gate =
  Access.list_access_points(scope)
  |> Enum.find(&(&1.name == "Main Gate")) ||
    halt("No 'Main Gate' access point — reseed with `mix ecto.reset`.")

{:ok, visitor} =
  Access.register_visitor(scope, %{
    "name" => "Demo Visitor",
    "company" => "Datem Demo Ltd",
    "host" => owner.email,
    "contact" => "demo.visitor@example.test"
  })

step("registered visitor ##{visitor.id} #{visitor.name}")

{:ok, %{pass: pass}} = Access.issue_pass(scope, visitor)
visitor_link = pass.gs1_identifier.digital_link

step("issued GSRN pass, valid #{pass.valid_from} → #{pass.valid_to}")
step("QR payload (GS1 Digital Link): #{visitor_link}")
step("QR renders as #{byte_size(Datem.GS1.qr_svg(visitor_link))} bytes of SVG on the pass page")

case Access.scan(scope, main_gate, visitor_link, operator) do
  {:ok, _log, entity, direction} ->
    accepted("scanned #{direction} at #{main_gate.name}: #{entity.name}")

  other ->
    halt("expected an accepted entry scan, got: #{inspect(other)}")
end

step("on site now: #{Access.list_onsite(scope) |> length()} subject(s)")

case Access.scan(scope, main_gate, visitor_link, operator) do
  {:ok, _log, entity, "out" = direction} ->
    accepted(
      "scanned #{direction} at #{main_gate.name}: #{entity.name} (direction inferred from the last log)"
    )

  other ->
    halt("expected an accepted exit scan, got: #{inspect(other)}")
end

## ---------------------------------------------------------------------
## 2. Ticketing: join link → ticket QR → check in → lunch → check out
## ---------------------------------------------------------------------

heading("2. Event ticketing")

event =
  Ticketing.list_events(scope)
  |> Enum.find(&(&1.name == "Acme Supplier Summit")) ||
    halt("No 'Acme Supplier Summit' event — reseed with `mix ecto.reset`.")

# Registration happens on the public join link, so it goes through the
# unauthenticated path: no caller scope, just the event and ticket type.
public_event = Ticketing.get_event_by_join_token(event.join_link_token)
general = Enum.find(public_event.ticket_types, &(&1.name == "General"))

step("public join link: /join/#{event.join_link_token}")

{:ok, ticket} =
  Ticketing.register_attendee(public_event, general, %{
    "attendee_name" => "Demo Attendee",
    "attendee_email" => "demo.attendee@example.test"
  })

ticket_link = ticket.gs1_identifier.digital_link

step("registered #{ticket.attendee_name} on a #{general.name} ticket (QR emailed via Oban)")
step("QR payload (GS1 Digital Link): #{ticket_link}")

case Ticketing.scan(scope, event, ticket_link, operator) do
  {:ok, _log, _ticket, "in"} -> accepted("checked in at the door")
  other -> halt("expected a check-in, got: #{inspect(other)}")
end

scan_types = Scanning.list_scan_types(scope)
entry = Enum.find(scan_types, &(&1.name == "Summit Entry"))
lunch = Enum.find(scan_types, &(&1.name == "Lunch"))
vip_lounge = Enum.find(scan_types, &(&1.name == "VIP Lounge"))

{:ok, %{result: :accepted}} = Scanning.scan(scope, entry, ticket_link, operator)
accepted("'#{entry.name}' checkpoint: accepted")

## Lunch, rule by rule.

heading("3. Checkpoint rules")

now = DateTime.utc_now() |> DateTime.truncate(:second)

# (a) Outside the active window.
{:ok, lunch} =
  Scanning.update_scan_type(scope, lunch, %{
    "active_from" => DateTime.add(now, -4, :hour),
    "active_to" => DateTime.add(now, -3, :hour)
  })

{:ok, %{result: result, message: message}} = Scanning.scan(scope, lunch, ticket_link, operator)
denied("lunch outside the 12:00–14:00 window → #{result}: #{message}")

# (b) Inside the window: accepted.
{:ok, lunch} =
  Scanning.update_scan_type(scope, lunch, %{
    "active_from" => DateTime.add(now, -1, :hour),
    "active_to" => DateTime.add(now, 1, :hour)
  })

{:ok, %{result: :accepted, message: message}} = Scanning.scan(scope, lunch, ticket_link, operator)
accepted("lunch inside the window → accepted: #{message}")

# (c) Second helping: once-per-attendee blocks it.
{:ok, %{result: result, message: message}} = Scanning.scan(scope, lunch, ticket_link, operator)
denied("second lunch scan → #{result}: #{message}")

# (d) VIP-only checkpoint with a General ticket.
{:ok, %{result: result, message: message}} =
  Scanning.scan(scope, vip_lounge, ticket_link, operator)

denied("VIP Lounge with a General ticket → #{result}: #{message}")

# (e) A QR from another tenant never resolves here.
other_link =
  Datem.GS1.Identifier
  |> where([i], i.organization_id != ^membership.organization_id)
  |> limit(1)
  |> Repo.one()

if other_link do
  {:error, :not_found} = Scanning.scan(scope, entry, other_link.digital_link, operator)
  denied("QR issued by another organisation → not_found (tenant isolation holds)")
end

## Check out.

heading("4. Check out")

case Ticketing.scan(scope, event, ticket_link, operator) do
  {:ok, _log, _ticket, "out"} -> accepted("checked out at the door")
  other -> halt("expected a check-out, got: #{inspect(other)}")
end

stats = Ticketing.event_stats(scope, event)
tallies = Scanning.tallies(scope, Enum.filter(scan_types, &(&1.event_id == event.id)))

heading("Live numbers (same figures the dashboard shows)")
step("registered: #{stats.registered} · checked in: #{stats.checked_in}")

for tally <- tallies do
  denominator = if tally.eligible, do: "/#{tally.eligible}", else: ""
  step("#{tally.scan_type.name}: #{tally.claimed}#{denominator} claimed")
end

IO.puts("""

\e[32mDemo complete.\e[0m Open the app to see the same data live:

  /dashboard        org overview
  /onsite           who is on site right now
  /events/#{event.id}         live event dashboard
  /checkpoints      operator checkpoint scanning
""")
