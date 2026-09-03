# Operator scanning guide

For the person standing at the gate, the door or the lunch queue. Everything
here works on a phone or tablet held in one hand.

---

## Before you start

- Log in at `/users/log-in` with the account your admin created for you.
- Allow the browser to use the **camera** when it asks. Without it you can still
  scan, but only by typing codes in by hand.
- Use **Chrome on Android**, or a recent Chromium-based browser. If the camera
  view doesn't appear, your browser doesn't support in-page barcode detection —
  use the manual entry box below the viewport, or switch device.
- Keep the screen awake and the device charged. Scanning needs a live
  connection; there is no offline queue yet.

---

## The three scanning views

| I'm scanning… | Go to | Then |
| ------------- | ----- | ---- |
| People and vehicles in and out of a site | `/scan` | Pick your access point (e.g. *Main Gate*) |
| Attendees in and out of an event | `/events` → the event → **Scan** | — |
| A checkpoint: lunch, a session, merch, a turnstile | `/checkpoints` | Pick the checkpoint |

`/checkpoints` only lists checkpoints that are **switched on and inside their
active window**. If the one you want isn't there, it isn't open yet — ask your
admin rather than scanning at the wrong one.

---

## Scanning

1. Open the view and point the camera at the QR code.
2. The code is read automatically — there is no button to press.
3. A large coloured result fills the screen.
4. Wait for the result before moving to the next person.

**If the camera won't read a code** — a cracked screen, a crumpled printout, low
light — use the manual entry field under the viewport and type or paste the code
shown under the QR. The result is exactly the same.

---

## What the results mean

| Result | Colour | Meaning | What to do |
| ------ | ------ | ------- | ---------- |
| **Accepted** | Green | Valid, rules passed. The name (and plate, for a vehicle) is shown | Let them through |
| **Duplicate** | Amber | Already used this checkpoint — e.g. a second lunch | Politely refuse, or call a supervisor if they insist |
| **Expired** | Red | The pass window has ended, or the checkpoint is outside its active time | Send them to reception / tell them when the checkpoint opens |
| **Denied** | Red | A rule failed: not checked in yet, wrong ticket type, missing an earlier checkpoint, or the pass was revoked | Read the message on screen — it says exactly which rule failed |
| **Not found** | Red | The code isn't one of your organisation's, or it isn't registered | Treat as invalid. A QR from another organisation will never work here |

Every scan — accepted or not — is recorded with your name against it. That is
normal and expected; it is the audit trail.

---

## Direction: in or out

You never choose in or out. Datem looks at the person's last scan and does the
opposite: first scan of the day checks them **in**, the next checks them **out**.

This also means an impossible sequence is refused: someone already inside cannot
be scanned **in** again without going out first. If that happens, either they
were scanned in at another gate, or a scan was missed — check the on-site view
at `/onsite` before overriding.

---

## Common situations

**"They forgot their QR."**
Ask reception or an admin to look them up on `/visitors` (or the event's attendee
list) and re-show or reissue the pass. Operators can't issue passes.

**"The code is on a phone that's dead."**
The pass can be reissued by an admin; there is no way to admit someone by name
from the scanning view, by design.

**"It says not checked in."**
The checkpoint requires the attendee to have been checked in at the door first.
Send them to the entrance to be checked in, then back.

**"It says VIP only."**
Their ticket type isn't on the allowed list for this checkpoint. Nothing you can
do from here — this is a ticketing decision.

**"The checkpoint disappeared from my list."**
Its active window closed or an admin switched it off. Nothing is broken.

**Someone is on site much longer than expected.**
`/onsite` flags visitors who have been inside for more than 12 hours, and warns
when a site hits its capacity. Flag it to your supervisor.

---

## Quick reference

- Green = through. Amber = already used. Red = stop and read the message.
- Never choose in/out — the system knows.
- Every scan is logged against you.
- If the camera fails, type the code in manually.
- If you're unsure, don't wave them through: call a supervisor.
