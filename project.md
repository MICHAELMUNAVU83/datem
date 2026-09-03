# Datem — Project Overview

**Datem** is a multi-tenant SaaS platform for **visitor access management** and **event ticketing**, built on GS1 identification standards. Organisations sign up, get an isolated workspace, and manage who and what enters their premises — people and vehicles — as well as run events with attendee check-in and configurable on-site scan actions (entry, exit, lunch, sessions, etc.).

Every scannable entity (visitor, attendee, vehicle, location) is identified using a GS1 standard identifier encoded as a **GS1 Digital Link** QR code, so scans are interoperable and unambiguous.

---

## 1. Goals & Principles

- **Two products, one platform.** Visitor Access Management and Ticketing share the same tenancy, identity, and scanning engine.
- **GS1-native.** Identifiers follow GS1 standards from day one rather than being bolted on later.
- **Real-time.** Live scan feeds, on-site counts, and dashboards update instantly via Phoenix LiveView + PubSub.
- **Multi-tenant with hard data isolation.** One organisation can never see another's data.
- **Configurable, not hard-coded.** Scan actions (lunch, entry, session A…) are defined by the organisation, not baked into the code.
- **Clean and minimal.** A restrained blue-and-white interface that stays out of the way.

---

## 2. Tech Stack

| Layer                 | Choice                                                          |
| --------------------- | --------------------------------------------------------------- |
| Language              | Elixir                                                          |
| Web framework         | Phoenix + Phoenix LiveView                                      |
| Real-time             | Phoenix PubSub, Phoenix Presence                                |
| Database              | PostgreSQL (via Ecto)                                           |
| Styling               | Tailwind CSS                                                    |
| QR generation         | `eqrcode` (SVG/PNG output)                                      |
| QR scanning (browser) | JS hook wrapping a camera library (e.g. `html5-qrcode` / ZXing) |
| Auth                  | `phx.gen.auth` (extended for org membership + roles)            |
| Background jobs       | `Oban` (email, exports, scheduled tasks)                        |
| Deployment            | Elixir releases on Fly.io (or equivalent), managed Postgres     |

---

## 3. Architecture

### 3.1 Multi-tenancy

**Approach: row-level tenancy with an `organization_id` on every tenant-owned table**, enforced through a scoping layer so queries can never accidentally cross tenants.

- Every schema that holds tenant data carries `organization_id` (FK, not null, indexed).
- All Ecto queries go through context functions that require an `%Organization{}` (or org id) and scope automatically — no context function returns data without a tenant.
- The current organisation is resolved once per LiveView session (from the user's active membership) and passed down; it is never taken from user-supplied params.
- A shared `Datem.Tenancy` helper adds a `where: x.organization_id == ^org_id` guard to every base query.

> Alternative considered: schema-per-tenant via `Triplex`. Row-level is simpler to operate, back up, and migrate, and is sufficient for the expected scale. Revisit only if a large tenant needs physical isolation.

### 3.2 Contexts (bounded modules)

- `Datem.Accounts` — users, sessions, credentials.
- `Datem.Organizations` — organisations, memberships, roles, invitations.
- `Datem.Identity` — GS1 identifier issuance (GLN, GSRN, GIAI), QR encoding, Digital Link resolution.
- `Datem.Access` — visitors, vehicles, passes, gates/access points, access logs.
- `Datem.Events` — events, ticket types, tickets/registrations, attendees, join links.
- `Datem.Scanning` — scan types/checkpoints, scan rules, scan logs. Shared by both modules.
- `Datem.Reporting` — aggregations, exports, live counts.

### 3.3 Real-time model

- Each scan writes a `scan_log`/`access_log` row and broadcasts on a topic like `org:{id}:site:{gln}` or `org:{id}:event:{id}`.
- Dashboards subscribe to those topics and update the live feed and counters without a refresh.
- `Phoenix.Presence` tracks who is currently on-site / checked in.

---

## 4. GS1 Standards Approach

Datem uses **GS1 Digital Link** as the QR payload format. A scanned code is a resolvable URI whose path carries a GS1 Application Identifier (AI) and the identifier value, e.g.:

```
https://id.datem.io/8018/095212345678900007
                     └AI┘ └──── GSRN value ────┘
```

| Entity                                      | GS1 identifier                                | AI                                          | Notes                                                                               |
| ------------------------------------------- | --------------------------------------------- | ------------------------------------------- | ----------------------------------------------------------------------------------- |
| Visitor / attendee                          | **GSRN** — Global Service Relation Number     | `8018`                                      | Identifies a person in a service relationship (visitor, event attendee). 18 digits. |
| Vehicle                                     | **GIAI** — Global Individual Asset Identifier | `8004`                                      | Identifies an individual asset. Good fit for a specific vehicle.                    |
| Site / gate / scan point                    | **GLN** — Global Location Number              | `414` (+ `254` extension for sub-locations) | Identifies physical locations and checkpoints. 13 digits.                           |
| Event / pass batch (optional serialisation) | Serial component                              | `21`                                        | Appended for per-issue uniqueness where needed.                                     |

**Company prefix dependency.** Fully compliant, globally-unique identifiers require a **GS1 Company Prefix**, which each organisation licenses from GS1. Datem should:

- Let an organisation configure its GS1 Company Prefix in settings.
- Generate structurally-valid identifiers (correct AIs, correct check digits) from that prefix.
- For organisations without a prefix, fall back to a Datem-namespaced internal identifier that is still Digital-Link-shaped, and clearly flag it as **not GS1-interoperable** until a real prefix is added.

**Check digits.** Implement the GS1 mod-10 check-digit algorithm for GLN/GSRN and validate on both generation and scan.

**Resolution.** `Datem.Identity` parses an incoming Digital Link URI, extracts the AI + value, validates the check digit, and looks up the owning entity within the scanning organisation's tenant scope.

---

## 5. Data Model (high level)

### Tenancy & identity

- **organizations** — name, slug, gs1_company_prefix, plan, settings.
- **users** — email, hashed_password, name.
- **memberships** — user_id, organization_id, role (`owner` | `admin` | `operator` | `viewer`).
- **invitations** — organization_id, email, role, token, status.
- **gs1_identifiers** — organization_id, kind (`gln` | `gsrn` | `giai`), value, ai, digital_link, subject_type, subject_id. Central registry of every issued identifier.

### Visitor access module

- **sites** — organization_id, name, gln, address.
- **access_points** — organization_id, site_id, name, gln (extension), direction rules.
- **visitors** — organization_id, name, contact, company, photo, host (optional), status.
- **visitor_passes** — organization_id, visitor_id, gsrn identifier, valid_from/valid_to, qr, status.
- **vehicles** — organization_id, plate, make/model, giai identifier, owner (visitor/host), qr.
- **access_logs** — organization_id, subject (visitor_pass | vehicle), access_point_id, direction (`in` | `out`), scanned_at, operator_id.

### Ticketing module

- **events** — organization_id, name, description, venue/site_id, starts_at, ends_at, status, join_link_token.
- **ticket_types** — event_id, name, price, quantity, per-attendee limits.
- **tickets / registrations** — event_id, ticket_type_id, attendee details, gsrn identifier, qr, status (`registered` | `checked_in` | `cancelled`).
- **attendees** — captured registration data (may be embedded in registrations).

### Shared scanning engine

- **scan_types** (a.k.a. checkpoints) — organization_id, scope (`event_id` or `site_id`), name (e.g. "Lunch", "Entry", "Session A"), rules (JSONB), active window.
- **scan_logs** — organization_id, scan_type_id, subject (polymorphic: visitor_pass | registration | vehicle), scanned_at, operator_id, result (`accepted` | `duplicate` | `expired` | `denied`), metadata.

---

## 6. Modules

### 6.1 Visitor Access Management

Track people and vehicles entering and leaving a site.

- **Visitor registration** — walk-in or pre-registered; capture name, company, host, optional photo. Issue a visitor pass with a GSRN QR.
- **Vehicle registration** — capture plate + details; issue a GIAI QR that can live on a windscreen tag.
- **Scan in / out** — an operator opens the scanning view at an access point, scans a QR, and the system records direction, validates the pass window, and prevents impossible transitions (e.g. two "in" scans with no "out").
- **On-site view** — live list of everyone currently inside, with time-in and host. Backed by Presence + access logs.
- **Pre-registration links** — a host can send a link so a visitor pre-fills details and receives their pass QR before arrival.
- **Alerts** — overdue visitors, denied scans, capacity thresholds.

### 6.2 Ticketing

Create and run events with attendee check-in and configurable on-site actions.

- **Event creation** — name, dates, venue, ticket types.
- **Attendee join link** — each event has a shareable link where people register and receive a ticket with a GSRN QR (emailed and/or shown in-browser).
- **Check-in / check-out** — scan attendees in and out at the door.
- **Dynamic scan actions** — organisers define their own scan types per event: "Lunch", "Welcome pack", "Session A", "Merchandise", etc. Each scan type has rules such as:
  - **Once per attendee** (e.g. one lunch), or **multiple**.
  - **Active time window** (lunch only valid 12:00–14:00).
  - **Requires prior scan** (must be checked in first).
  - **Allowed ticket types** (VIP-only lounge).
  - On scan, the engine evaluates the rules and returns `accepted` / `duplicate` / `expired` / `denied` with a clear operator message.
- **Live event dashboard** — registered vs checked-in counts, per-scan-type tallies (e.g. 240/300 lunches claimed), live feed.

### 6.3 Shared scanning engine

Both modules feed the same engine: parse Digital Link → resolve identifier in tenant scope → find scan type → evaluate rules → write log → broadcast. This keeps behaviour consistent and means new scan types are configuration, not code.

---

## 7. Design System

**Aesthetic:** clean, minimal, blue and white. Generous whitespace, restrained typography, no visual clutter.

- **Palette**
  - Primary: blue-600 `#2563EB` (actions, active states)
  - Primary hover/dark: blue-700 `#1D4ED8`
  - Surface: white `#FFFFFF`
  - App background: gray-50 `#F9FAFB`
  - Text: gray-900 / gray-600 for secondary
  - Borders: gray-200
  - Status: green (accepted/in), amber (warning/duplicate), red (denied/expired)
- **Typography:** one clean sans-serif (e.g. Inter). Clear hierarchy, few weights.
- **Layout:** left sidebar navigation (module switch + sections), top bar with org switcher and user menu, roomy content area with cards.
- **Components:** buttons, inputs, tables with empty states, stat cards, live feed rows, QR display, a full-screen scanning view optimised for a phone/tablet held at a gate.
- **Scanning view:** large camera viewport, big accept/deny result state (colour + icon + name), minimal chrome, one-handed friendly.
- **Responsive:** desktop for admin/config, mobile/tablet-first for the scanning views used on-site.

---

## 8. Security & Compliance

- **Tenant isolation** enforced in the data layer, not just the UI (see §3.1). Add tests that assert cross-tenant access is impossible.
- **Roles & permissions** — owner/admin/operator/viewer; operators can scan but not export or edit config.
- **Auth** — hashed passwords, session management via `phx.gen.auth`; consider 2FA for admins.
- **PII** — visitor/attendee data is personal data. Support data retention windows, export, and deletion per organisation. Store photos in object storage with signed URLs.
- **Audit** — access_logs and scan_logs are the audit trail; log who scanned what and when.
- **QR integrity** — validate GS1 check digits; scope resolution to the scanning org so a QR from org A can't be used at org B.

---

## 9. Non-Functional Requirements

- Scan-to-result latency should feel instant on-site (< ~300 ms server processing).
- Scanning views should tolerate flaky connectivity (queue scans and reconcile where feasible — see open questions).
- Exports (CSV) for access logs, attendee lists, and scan tallies run via Oban.
- Observability: telemetry on scan volume, denials, and latency.

---

## 10. Open Questions / Decisions To Make

- **Offline scanning:** do on-site scanners need to work without connectivity, or is reliable Wi-Fi/4G assumed? (Affects whether we queue scans client-side.)
- **Payments:** are paid tickets in scope for v1, or free registration only? (Adds Stripe + reconciliation.)
- **GS1 prefixes:** will Datem require each org to bring its own GS1 Company Prefix, or issue internal identifiers by default with an upgrade path?
- **Native app:** is a browser-based scanner (camera via JS hook) enough, or is a dedicated mobile app needed for hardware scanners?
- **Notifications:** email only, or SMS/WhatsApp for passes and links?
- **Vehicle recognition:** manual QR only, or future ANPR/plate-reading integration?

---

## 11. Roadmap Snapshot

- **v1 (MVP):** tenancy + auth, GS1 identity, visitor access with scan in/out, live on-site view, one event with join link + check-in, basic dynamic scan types, blue/white design system.
- **v1.1:** vehicle management, richer scan rules, exports, dashboards.
- **v2:** offline scanning, payments, notifications, ANPR, API for integrations.

See `tasks.md` for the phased build breakdown.
