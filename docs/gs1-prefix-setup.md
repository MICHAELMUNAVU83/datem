# GS1 Company Prefix setup guide

For organisation **owners** and **admins**. Ten minutes of setup that decides
whether your QR codes are globally meaningful or only meaningful inside Datem.

---

## 1. What a GS1 Company Prefix is

A **GS1 Company Prefix** is a number licensed to your organisation by your local
GS1 member organisation. It is the part of every GS1 identifier that says *"this
was issued by us"* — nobody else in the world can issue an identifier that
starts with your prefix.

It is 6 to 10 digits long. The shorter the prefix, the more identifiers you can
issue behind it.

Datem uses it to build three kinds of identifier:

| Entity | Identifier | AI | Shape |
| ------ | ---------- | -- | ----- |
| Site, gate, checkpoint | **GLN** — Global Location Number | `414` | 13 digits: prefix + location reference + check digit |
| Visitor pass, event ticket | **GSRN** — Global Service Relation Number | `8018` | 18 digits: prefix + service reference + check digit |
| Vehicle | **GIAI** — Global Individual Asset Identifier | `8004` | prefix + an asset reference |

Every QR code Datem prints is a **GS1 Digital Link** — a real URL carrying the
AI and the value:

```
https://id.datem.io/8018/095212345678900007
                    │    └──── GSRN value ────┘
                    └─ AI: this is a GSRN
```

GLN and GSRN values carry a **GS1 mod-10 check digit**. Datem validates it both
when issuing and on every scan, so a damaged or tampered-with code is rejected
before it can resolve to anyone.

---

## 2. What happens if you don't have one

Datem works fine without a prefix. It falls back to a reserved internal prefix
(`0999999`) and issues identifiers that are structurally valid and
Digital-Link-shaped — correct AIs, correct check digits — but marked
**`interoperable: false`**.

| | With your own prefix | With the internal fallback |
| --- | --- | --- |
| Scanning inside Datem | Works | Works |
| Check digits valid | Yes | Yes |
| Globally unique | Yes | No — only unique within Datem |
| Readable by third-party GS1 systems | Yes | No |
| Safe to print on badges shared with partners | Yes | Not recommended |

So: start without one if you need to run tomorrow, but get one before your
identifiers leave your own walls.

---

## 3. Getting a prefix

1. Find your **local GS1 member organisation** (there is one per country — see
   <https://www.gs1.org/contact>).
2. Apply for a company prefix. You will be asked about your organisation and
   roughly how many identifiers you expect to issue.
3. GS1 issues the prefix, usually against an annual licence fee.
4. Note the prefix exactly as issued, including any leading zeros — they are
   part of the number.

Licence one prefix per **legal entity**, not per site or per event. All of your
sites, passes and tickets are issued behind the same prefix.

---

## 4. Adding it to Datem

1. Log in as an owner or admin.
2. Go to **`/organization/settings`**.
3. Enter the prefix in **GS1 Company Prefix** and save.

Datem validates that it is 6–10 digits. Leading zeros are preserved; spaces are
trimmed. Anything else is rejected with *"must be 6 to 10 digits, as licensed
from GS1"*.

---

## 5. What changes after you add it

**Identifiers issued from now on** use your prefix and are marked interoperable.

**Identifiers issued before** — existing site GLNs, live passes, tickets already
in attendees' inboxes — keep the internal prefix. They are not rewritten, because
QR codes already in the wild would stop matching.

So plan the switch:

- **Best case:** add the prefix before you create your sites and access points,
  and before you open a join link.
- **If you're already live:** the practical route is to reissue. Recreate sites
  and access points to get new GLNs, revoke and reissue visitor passes, and
  regenerate tickets before an event opens. For a long-running site, it is
  usually acceptable to let old passes expire naturally and only issue new ones
  behind the real prefix.

Either way, nothing breaks in the meantime: both old and new codes resolve and
scan.

---

## 6. Structure and capacity

Everything behind the prefix is Datem's to allocate; you don't need to design a
numbering scheme. Datem generates the reference digits, retries on collision, and
appends the check digit.

Rough capacity, given a prefix of length *p*:

- **GLN**: 10^(12−*p*) locations — a 7-digit prefix gives 100,000 sites and gates.
- **GSRN**: 10^(17−*p*) service relations — a 7-digit prefix gives 10^10 passes
  and tickets, which is not a limit you will meet.

If you do run short, GS1 can issue you a shorter prefix.

---

## 7. Checking it worked

- `/organization/settings` shows the saved prefix.
- Create a test site on `/sites`: its GLN should begin with your prefix.
- Register a test visitor, issue a pass, and open `/visitors/:id`: the Digital
  Link under the QR should read `https://id.datem.io/8018/<your prefix>…`.
- Scan that QR at an access point. Accepted means the check digit validated and
  the identifier resolved inside your tenant.

A QR issued by another organisation will never resolve in yours — resolution is
scoped to the scanning organisation, whatever the code says.

---

## 8. Troubleshooting

| Symptom | Cause |
| ------- | ----- |
| "must be 6 to 10 digits" | Non-digits, or the wrong length. Enter digits only, no dashes or spaces |
| New codes still start `0999999` | The prefix wasn't saved, or you are looking at an identifier issued before you saved it |
| A partner's scanner can't read your badge | The badge was issued under the internal fallback prefix. Reissue it |
| A scan says *not found* | The code belongs to another organisation, or the entity was deleted. Check digits are validated first, so a *not found* means resolution failed, not that the code was malformed |
