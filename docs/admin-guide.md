# Datem admin guide

For organisation **owners** and **admins**. It covers everything from first
login to running an event and pulling the numbers afterwards.

---

## 1. Your organisation

When you register at `/users/register`, Datem creates an organisation and makes
you its **owner**. Everything you go on to create — sites, visitors, events,
scans — belongs to that organisation and is invisible to every other one.

### Roles

| Role | Can do |
| ---- | ------ |
| **owner** | Everything, including organisation settings and members |
| **admin** | Everything except transferring ownership: configure, scan, report, export |
| **operator** | Scan at access points and checkpoints, and see scan results. No configuration, no exports |
| **viewer** | Read-only: dashboards and reports. No scanning, no exports |

Roles are enforced in the data layer, not just hidden in the UI, so an operator
cannot reach an export by typing its URL.

### Inviting people — `/organization/members`

1. Enter the person's email and pick a role.
2. Datem emails them an invitation link (`/invitations/:token`).
3. They accept, and the membership is created. Pending invitations are listed on
   the same page and can be revoked.

If someone belongs to more than one organisation, their session is tied to one
active organisation at a time; switching is handled by
`/organizations/switch/:organization_id`.

### Settings — `/organization/settings`

Set the organisation name and the **GS1 Company Prefix**. Adding a prefix is the
single most important setup step for interoperability — see the
[GS1 prefix setup guide](gs1-prefix-setup.md). Without one, Datem still works:
it issues Digital-Link-shaped internal identifiers, flagged as *not
GS1-interoperable*.

---

## 2. Visitor access management

### Sites — `/sites`

A site is a physical location: a head office, a plant, a venue. Each site gets a
**GLN** (Global Location Number) automatically on creation.

Set the optional **capacity** to have Datem raise a capacity alert on the
dashboard when the number of people on site reaches it.

### Access points — `/access-points`

An access point is a gate, door or turnstile belonging to a site — the place an
operator stands. Each one gets its own GLN extension. Create at least one per
site before anyone tries to scan.

### Visitors — `/visitors`

Two ways in:

- **Walk-in.** Register the visitor on `/visitors` (name, company, host,
  contact, optional photo), then issue a pass.
- **Pre-registration.** Create a pre-registration link and send it to the
  visitor. They fill in their own details at `/visit/:token` and receive their
  pass QR before they arrive.

**Issuing a pass** mints a **GSRN** identifier and a validity window (24 hours by
default) and renders the GS1 Digital Link as a QR code on the visitor's page
(`/visitors/:id`) for printing or screenshotting. Revoking a pass takes effect on
the next scan immediately.

### Vehicles — `/vehicles`

Register a plate with make and model and Datem issues a **GIAI** identifier and a
windscreen-tag QR. Vehicles scan in and out exactly like visitors.

### Live on-site view — `/onsite`

Everyone and everything currently inside, with time-in and host, updating in
real time as scans happen. Denied scans stream into the same view. Alerts appear
here and on the dashboard for visitors on site longer than 12 hours and for
sites at or over capacity.

---

## 3. Ticketing

### Events — `/events`

Create the event (name, description, venue, start and end). Then:

1. **Add ticket types** — name, price, quantity and per-attendee limit. Quantity
   is enforced: once it is exhausted, registration is refused as sold out.
2. **Generate the join link** — a public URL, `/join/:token`, that anyone can
   use to register. Share it however you like; no Datem account is needed.
3. Attendees who register receive a **GSRN** ticket QR in the browser and by
   email (sent in the background via Oban).

### Live event dashboard — `/events/:id`

Registered vs checked-in counts, per-checkpoint tallies (e.g. "240/300 lunches
claimed") and a live feed of scans as they happen.

### Check-in / check-out — `/events/:id/scan`

The door scanner for the event. Direction alternates automatically: a first scan
checks the attendee in, the next checks them out.

---

## 4. Checkpoints (dynamic scan types) — `/scan-types`

A checkpoint is any scan action you want to run beyond the door: **Lunch**,
**Welcome pack**, **Session A**, **Merch**, **HQ Turnstile**. Checkpoints are
configuration, not code — create as many as you need.

Each checkpoint belongs to exactly one **scope**: an event *or* a site.

**Rules**, evaluated on every scan:

| Rule | Effect |
| ---- | ------ |
| **Once per attendee** | The second accepted scan by the same person is a `duplicate`. Turn off for repeatable checkpoints like a turnstile |
| **Active window** | The checkpoint only accepts scans between `active_from` and `active_to` (e.g. lunch 12:00–14:00). Outside it, scans are `expired` |
| **Requires check-in** | The attendee must have been checked in at the door first |
| **Requires a prior checkpoint** | The attendee must have an accepted scan at a named earlier checkpoint |
| **Allowed ticket types** | Only listed ticket types are accepted (e.g. VIP lounge) |

The **on/off switch** on each checkpoint is separate from the window: switching a
checkpoint off hides it from operators immediately, whatever the clock says.

When several rules fail at once, the operator is shown the most general reason
first — "this checkpoint is switched off" beats "you already had lunch" — so the
message is the one they can act on.

Every scan attempt is written to the audit trail, denials included.

---

## 5. Reporting and exports

| Page | Shows |
| ---- | ----- |
| `/dashboard` | Today's visitors on site, active events, recent denials, alerts — live |
| `/reports/access` | Entries and exits by site, access point and day, over a date range |
| `/reports/events` | Attendance, check-in rate and per-checkpoint breakdown, live |
| `/exports` | CSV exports of access logs, attendee lists and scan tallies |

Reports are open to owner, admin and viewer. **Exports are owner and admin only** —
an export file is a bundle of personal data, so operators cannot generate or
download one.

Exports run in the background: request one, and the row on `/exports` updates
itself to *ready* with a download link when the file is written. Files are stored
outside the public asset directory and served only after a tenant and role check.

---

## 6. Setting up for a real event — checklist

1. Add your GS1 Company Prefix in `/organization/settings`.
2. Create the site and its access points.
3. Create the event, its ticket types, and generate the join link.
4. Create the checkpoints you need, with their rules and windows.
5. Invite your gate staff as **operators**.
6. Share the join link; attendees register and get their QR.
7. On the day: operators open `/checkpoints` (or `/scan` for site access) on a
   phone or tablet and start scanning. See the
   [operator scanning guide](operator-scanning-guide.md).
8. Afterwards: `/reports/events`, then export the CSVs you need.

---

## 7. Data protection

Visitor and attendee records are personal data. Keep exports to the people who
need them, revoke passes when a visit ends, and remember that `access_logs` and
`scan_logs` are your audit trail — who scanned what, where, and when.
