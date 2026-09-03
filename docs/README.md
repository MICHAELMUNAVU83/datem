# Datem documentation

| Guide | For | Contents |
| ----- | --- | -------- |
| [Admin guide](admin-guide.md) | Owners and admins | Setting up an organisation, sites, visitors, events, checkpoints, reports and exports |
| [Operator scanning guide](operator-scanning-guide.md) | Gate and door staff | How to scan, what each result means, what to do when a scan is denied |
| [GS1 prefix setup guide](gs1-prefix-setup.md) | Owners and admins | What a GS1 Company Prefix is, how to add one, and what changes when you do |

## Demo data

The repository ships with demo data and a scripted end-to-end run:

```bash
mix ecto.reset             # creates the database and runs priv/repo/seeds.exs
mix demo                   # runs priv/repo/demo.exs against the seeded org
mix phx.server             # then log in at http://localhost:4000/users/log-in
```

Seeded logins (password `datem-demo-password` for all of them):

| Email | Role |
| ----- | ---- |
| `owner@datem.test` | owner of *Acme Manufacturing* |
| `admin@datem.test` | admin |
| `operator@datem.test` | operator — can scan, cannot configure or export |
| `viewer@datem.test` | viewer — read-only |
| `northwind@datem.test` | owner of a second organisation, used to show tenant isolation |

`mix demo` walks the full path — register a visitor, issue a GSRN QR, scan in,
scan out; register an attendee on the public join link, check in, lunch scan
(denied outside the window, accepted inside, duplicate on the second try),
VIP-only denial, cross-tenant QR rejection, check out — printing each step and
the resulting live counters. It is safe to run repeatedly; each run adds one
more visitor and one more attendee.
