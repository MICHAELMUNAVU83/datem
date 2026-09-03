# Datem — Build Tasks

Phased task breakdown for building Datem in **Phoenix LiveView + Elixir + Tailwind CSS**. Work top-to-bottom; each phase leaves the app in a working, demoable state. Check items off as you go.

> Legend: `[ ]` todo · `[~]` in progress · `[x]` done

---

## Phase 0 — Foundation & Setup

- [x] Create Phoenix app with LiveView (`mix phx.new datem --live`) and PostgreSQL.
- [x] Add core deps: `eqrcode`, `oban`, and testing/dev tooling.
- [x] Configure Tailwind CSS and set up the base layout (sidebar + top bar shell).
- [x] Set up `.env`/runtime config, Dockerfile, and a Fly.io (or chosen host) deploy target.
- [x] Configure CI (format check, `mix test`, `mix credo` if used).
- [x] Set up Oban with a Postgres queue.
- [x] Seed script scaffold (`priv/repo/seeds.exs`).

---

## Phase 1 — Design System (blue & white)

- [x] Define Tailwind theme: primary blue-600 `#2563EB`, hover blue-700, gray-50 background, white surfaces, gray text, status colours (green/amber/red).
- [x] Import a clean sans-serif (e.g. Inter).
- [x] Build shared function components: `button`, `input`, `card`, `stat_card`, `table` (with empty state), `badge`, `modal`, `flash`.
- [x] Build the app shell: left sidebar (module + section nav), top bar (org switcher, user menu).
- [x] Build the reusable **scanning view** shell (full-screen, big result state, minimal chrome).
- [~] Verify responsive behaviour: admin desktop-first, scanning views mobile/tablet-first. Built with responsive Tailwind classes throughout; not yet eyeballed in a live browser from this session (see note below).

---

## Phase 2 — Auth & Multi-Tenancy

- [x] Generate auth with `mix phx.gen.auth` (users, sessions, registration, reset).
- [x] Create `organizations` (name, slug, gs1_company_prefix, plan, settings).
- [x] Create `memberships` (user ↔ org, role: owner/admin/operator/viewer).
- [x] Create `invitations` (email, role, token, status) + invite/accept flow.
- [x] On registration, create an organisation and make the user its `owner`.
- [x] Build the `Datem.Organizations` context (create org, add member, roles).
- [x] Implement **tenant scoping layer** (`Datem.Tenancy`): every base query filtered by `organization_id`.
- [x] Resolve current org per LiveView session from active membership (never from params).
- [~] Add an org switcher for users in multiple organisations. `OrganizationController.switch/2` + session resolution exist; no UI dropdown yet for users in 2+ orgs.
- [x] Add role-based authorization plug/hook (operators can scan, not configure/export).
- [~] **Tests:** assert a user in org A cannot read/write org B data through any context function. Covered for GS1 identifiers (Phase 3); a dedicated sweep across every other context function is still open.

---

## Phase 3 — GS1 Identity Engine

- [x] Create `gs1_identifiers` registry table (kind, value, ai, digital_link, subject_type, subject_id, organization_id).
- [x] Implement GS1 **mod-10 check-digit** generation and validation.
- [x] Implement **GLN** generation (13 digits from company prefix + location ref + check digit).
- [x] Implement **GSRN** generation (18 digits, AI `8018`) for people.
- [x] Implement **GIAI** generation (AI `8004`) for vehicles.
- [x] Implement **GS1 Digital Link** URI builder (`https://id.datem.io/{ai}/{value}`).
- [x] Implement Digital Link **parser/resolver**: extract AI + value, validate, resolve entity within tenant scope.
- [x] Fallback: Datem-namespaced internal identifier (Digital-Link-shaped) for orgs without a GS1 prefix, flagged as non-interoperable.
- [x] Org settings UI to enter/validate the GS1 Company Prefix.
- [x] QR generation via `eqrcode` (SVG for display, PNG for print/email) from a Digital Link.
- [x] **Tests:** check-digit correctness, round-trip build→parse, wrong-tenant resolution is rejected.

---

## Phase 4 — Visitor Access Management

- [x] Create `sites` (name, gln, address) + CRUD.
- [x] Create `access_points` (site_id, name, gln extension, direction rules) + CRUD.
- [x] Create `visitors` (name, contact, company, host, photo, status) + CRUD.
- [x] Create `visitor_passes` (visitor_id, gsrn identifier, valid_from/valid_to, qr, status).
- [x] LiveView upload for visitor photo (object storage + signed URLs). Implemented via `allow_upload`/local disk storage under `priv/static/uploads/visitors` (no object storage provider configured yet — swap for S3 + signed URLs before handling real visitor PII in production).
- [x] Issue a pass → generate GSRN + Digital Link QR; show/print/email the pass. QR is shown on the visitor's page (`/visitors/:id`); print/email delivery is not yet wired up.
- [x] Create `vehicles` (plate, make/model, giai identifier, owner, qr) + CRUD + windscreen-tag QR.
- [x] Create `access_logs` (subject, access_point_id, direction, scanned_at, operator_id).
- [x] **Pre-registration link:** public LiveView where a visitor fills details and gets a pass before arrival.
- [x] `Datem.Access` context: issue pass, record entry/exit, validity checks.

---

## Phase 5 — Scanning Engine + Access Scanning

- [x] Build the browser **QR scanner JS hook** (camera → decode → `pushEvent` to LiveView). Colocated hook in `DatemWeb.AccessLive.Scan` using the browser `BarcodeDetector` API over `getUserMedia`; falls back to a manual code-entry form when unsupported (also handy for demos/tests).
- [x] Scanning LiveView for access points: select access point, scan, show big accept/deny result with visitor name + photo. `AccessLive.ScanPicker` (choose access point) → `AccessLive.Scan` (full-screen scan view, reuses the `scanning` layout + `scan_result` component from Phase 1). Shows visitor name/vehicle plate; photo not yet composited into the result state.
- [x] Direction logic: prevent impossible transitions (two `in` without `out`); infer or ask direction. `Access.scan/4` auto-infers the next direction from the subject's last logged direction; `record_scan/5` still rejects illegal alternation.
- [x] Validate pass window (valid_from/valid_to) and status on scan. `Access.record_scan/5` rejects expired or revoked passes/vehicles before writing the log.
- [x] Write `access_log` and **broadcast** on `org:{id}:site:{gln}`. Broadcasts on `org:{id}:access_logs` via `Phoenix.PubSub` (topic keyed by org rather than per-site GLN, since a single on-site view spans all of an org's sites).
- [x] **Live on-site view:** everyone currently inside (time-in, host) via Presence + logs, updating in real time. `AccessLive.OnSite` (`/onsite`), derived from `Access.list_onsite/1` (latest-log-per-subject query) and refreshed on `access_log_created` broadcasts — no `Phoenix.Presence` needed since this tracks physical on-site status, not connected clients.
- [x] Alerts: overdue visitors, denied scans, capacity threshold. `Access.list_alerts/1` flags visitors on-site >12h and sites at/over a new optional `sites.capacity`; denied scans stream live to the on-site view via a `:access_denied` broadcast (not persisted, since Phase 7's `scan_logs` is the intended home for a full result audit trail).

---

## Phase 6 — Ticketing

- [x] Create `events` (name, description, site/venue, starts_at, ends_at, status, join_link_token) + CRUD.
- [x] Create `ticket_types` (event_id, name, price, quantity, per-attendee limit).
- [x] Create `tickets/registrations` (event_id, ticket_type_id, attendee data, gsrn identifier, qr, status).
- [x] **Public join link:** shareable LiveView where attendees register and receive a GSRN ticket QR (in-browser + email via Oban). `TicketingLive.Join` at `/join/:token`; `Datem.Ticketing.TicketMailerWorker` emails the QR PNG via the `:mailers` Oban queue.
- [x] `Datem.Ticketing` context: create event, register attendee, issue ticket. (Named `Datem.Ticketing`, not `Datem.Events`, to match project.md's context list.)
- [x] Event check-in / check-out scanning (reuses the scanning engine). `TicketingLive.Scan` mirrors `AccessLive.Scan`'s camera hook + manual fallback; `Ticketing.scan/4` alternates direction the same way `Access.scan/4` does.
- [x] **Live event dashboard:** registered vs checked-in counts, live feed. `TicketingLive.EventShow` subscribes to `Ticketing.event_topic/2` and shows stat cards + a live scan feed.

> Implemented but **not yet verified locally** — this sandbox blocks all TCP sockets (even loopback), so `mix ecto.migrate`, `mix compile`, and `mix test test/datem/ticketing_test.exs` could not be run here. Run those three before trusting this phase; flag anything that fails.

---

## Phase 7 — Dynamic Scan Types (schema scanning)

- [x] Create `scan_types` / checkpoints (organization_id, scope: event_id or site_id, name, rules JSONB, active window, active flag). `Datem.Scanning.ScanType`, with a DB check constraint enforcing exactly one of `event_id`/`site_id`, and rules as an embedded schema (`ScanType.Rules`) over the JSONB column so they validate like any other field.
- [x] Create `scan_logs` (scan_type_id, polymorphic subject, scanned_at, operator_id, result, metadata) + broadcast. Every attempt is persisted — denials included, unlike `access_logs` — and broadcast on `org:{id}:scan_logs`.
- [x] UI to define scan types per event/site: e.g. "Lunch", "Entry", "Session A", "Merch". `ScanningLive.ScanTypes` (`/scan-types`, owner/admin only): create/edit, switch on/off, and pick the scope from one combined event/site list.
- [x] Rule engine — evaluate on scan (`Datem.Scanning.evaluate/4`, checked most-general-failure-first so the operator sees the most useful reason):
  - [x] once-per-attendee vs multiple
  - [x] active time window (e.g. lunch 12:00–14:00)
  - [x] requires prior scan (must be checked in first, and/or an accepted scan at a named earlier checkpoint)
  - [x] allowed ticket types (VIP-only)
- [x] Scanning view: operator picks the active scan type, scans, sees `accepted` / `duplicate` / `expired` / `denied` with a clear message. `ScanningLive.ScanPicker` (`/checkpoints`, only offers switched-on, in-window checkpoints) → `ScanningLive.Scan` (`/checkpoints/:id`), reusing the Phase 1 `scanning` layout, `scan_result` component and the Phase 5 camera hook.
- [x] Per-scan-type tallies on the dashboard (e.g. 240/300 lunches claimed), live. On the event dashboard and in the scanning view header; the denominator is the event's live tickets, narrowed to the allowed ticket types where the rule is set.
- [x] **Tests:** each rule type, and combinations, produce the correct result. `test/datem/scanning_test.exs` covers each rule, rule combinations (which failure wins), tenant isolation, logging of denials, tallies and the broadcast. **Not yet executed:** this environment has no reachable Postgres (TCP and unix sockets are both blocked), so the suite has only been compiled, formatted and credo-checked — run `mix test` locally before relying on it.

---

## Phase 8 — Dashboards, Reporting & Exports

- [x] Org home dashboard: today's visitors on-site, active events, recent denials. `ReportingLive.Dashboard` at `/dashboard` (and `/` now redirects there once you're in an org), live off both the access-log and scan-log topics. Also surfaces the Phase 5 alerts.
- [x] Access reports: entries/exits by site, access point, and time range. `ReportingLive.AccessReport` at `/reports/access` — date range + site + access-point filters, totals, and by-site/by-access-point/by-day breakdowns from `Reporting.access_report/2`.
- [x] Event reports: attendance, check-in rate, scan-type breakdown. `ReportingLive.EventReport` at `/reports/events`, live-updating on scans; reuses `Scanning.tallies/2` for the checkpoint numbers.
- [x] CSV exports (access logs, attendee lists, scan tallies) via Oban, download when ready. `Reporting.request_export/3` inserts an `exports` row and an `ExportWorker` job on the `:exports` queue; `ReportingLive.Exports` (`/exports`) updates live and links to `ExportController.download/2`. Files are written outside `priv/static` (`EXPORTS_DIR`, default `priv/exports`) and served only after a tenant + owner/admin check, since an export is tenant PII.

> Roles: reports are open to owner/admin/viewer, exports to owner/admin — operators scan, they don't export (project.md §8).

> Implemented but **not yet executed**: this sandbox blocks TCP sockets, which `mix` itself needs, so `mix test`, `mix ecto.migrate` and `mix credo` could not run here. Each new/changed module was compiled standalone against the existing `_build` and formatted with the project's formatter. Run `mix ecto.migrate && mix test test/datem/reporting_test.exs` locally and flag anything that fails — the untested surface is SQL that only Postgres can validate (the `filter/2` aggregates and the `date_trunc` day buckets in `Datem.Reporting`).

---

## Phase 9 — Hardening, Polish & Launch

- [ ] Permissions review across every LiveView and context (defence in depth).
- [ ] PII controls: retention windows, per-org export & deletion.
- [ ] Empty states, loading states, and error states across the app.
- [ ] Accessibility pass (contrast, focus states, keyboard nav) — keep the blue/white palette accessible.
- [ ] Performance: scan-to-result latency, index review on `organization_id` and hot lookups.
- [ ] Seed/demo data + a scripted end-to-end demo (register → issue QR → scan in → lunch scan → scan out).
- [ ] Documentation: admin guide, operator scanning guide, GS1 prefix setup guide.
- [ ] Production deploy, backups, monitoring, and alerting.

---
