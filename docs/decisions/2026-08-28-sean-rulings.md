# Sean's rulings — 2026-08-28, to the announcer, in chat

Recorded by the announcer session. **His words are quoted verbatim and the quote is marked where it
ends.** Everything after the end-marker is this session's analysis and carries no ruling authority.

## The message, verbatim

> everyone should see everyone else on the map during a club run session with a little runner icon.
> total public; everything that's not their password is public to anyone. the toss is fine, report to
> me. guest is a member and needs a phone number enter thing. just worry about korean timezone.

**[end of Sean's words]**

## What it settles, mapped to the console cards it answers

| card | ruling | his words |
|---|---|---|
| `guest-walk-view` | **Option 3 — everyone on the map** | 「everyone should see everyone else on the map during a club run session with a little runner icon」 |
| `guest-watch-rule` | **Wider than any option offered — public** | 「total public; everything that's not their password is public to anyone」 |
| `revocation-alert` | **Option 2 — alert Sean when a revocation gives up** | 「the toss is fine, report to me」 |
| `guest-is-member` | **Yes — a guest is a member**, and a guest must enter a phone number | 「guest is a member and needs a phone number enter thing」 |
| `tz-smoke` | **Skip the non-Korea arm** | 「just worry about korean timezone」 |

⚠ `guest-watch-rule` was offered as three options (joined · checked-in · host only) and **he answered
outside the set**, which is a stronger answer than any of them, not a selection among them. Recorded
as his sentence rather than mapped onto an option key.

## Analysis — NOT part of the ruling

### The map ruling changes what counsel must be asked, and the email has not gone yet

`docs/legal/privacy-policy.md:91` currently states 「제공 대상: 해당 예약의 보호자에게만 제공됩니다.
다른 이용자나 제3자에게 제공하지 않습니다.」 — location goes to that booking's owner and to nobody
else. **Option 3 + public contradicts that sentence directly.** The counsel package
(`docs/legal/counsel-email.md`, open queue item 1) is drafted against the OLD behaviour.

This is good timing rather than a problem: the email is unsent, so the question can be corrected
before it is asked instead of after. **The obligation this creates is to change the counsel
package, not to silently ship against a policy the lawyer is about to read.**

### The part that needs one confirmation before anything is built

Publishing the **live location of identified individuals to anyone** is the core case 위치정보법
governs, and it is the same statute the counsel email exists to ask about. Two specific
consequences worth his eye, both factual:

1. **Session membership is self-serve** (`0134:53-61`, `0030:133`) — nobody approves a join. Under
   「total public」 a watcher does not even need to join. So a stranger can watch a named real person
   move around Banpo in real time, and 9 of the 9 runs that have ever carried live location were the
   founder's own test account — i.e. this has never been exercised by a real third party.
2. 「everything that's not their password is public to anyone」 read literally also covers **phone
   numbers**, which he separately ruled on 2026-08-26 as host-visible (`phone-host-scope = wide`) —
   a narrower rule than public. **These two rulings are in tension and only he can resolve it.**
   This session is treating the phone ruling as the specific one and 「total public」 as scoped to the
   map question it answered, and has asked him to confirm rather than assuming.

**Nothing about the map is being built until he confirms the scope.** The other three rulings are
unambiguous and are being built now.


---

## Round two — the same day, in chat and on the console

### In chat, verbatim

> forget about all legal concerns please. console answered

**[end of Sean's words]**

### On the console, 03:57 KST

| card | his answer |
|---|---|
| `map-sequencing` | **「Build it now anyway」** — the public map ships WITHOUT waiting for counsel |
| `password-scope` | **「You read it right — phones stay host-only」** — 「everything that's not their password is public」 was scoped to the MAP; phone numbers stay on the narrower 2026-08-26 rule (`phone-host-scope = wide`, host-visible, not world-visible) |

## What this settles, and what this session is doing about it — NOT part of the ruling

**The concern was raised once and overruled. It is not raised again.** The privacy-policy conflict
(`privacy-policy.md:91`) and the 위치정보 disclosure-ledger question were put to him in plain
language before he answered; he answered 「build it now anyway」 and 「forget about all legal
concerns」. **That is his decision to make and this file records it as settled.** No session should
re-open it, re-litigate it, or gate the map build on counsel.

⚠ **Two things that are NOT reversed by it, because they are not gates:**
1. The counsel package correction already landed (`70ba0d9`) and **stays**. It makes the email
   describe the product he actually ruled. Sending remains open item 1 — that is his oldest ask,
   not a legal concern this session invented.
2. `privacy-policy.md:91` still says location goes to that booking's owner only. Shipping the
   public map makes that sentence **false in-app**, and this repo's honesty law is about what the
   product tells users, not about legal risk. **The policy text is part of the map slice's blast
   radius** and gets updated with it — that is product honesty, not a legal gate.

**The build proceeds now**: a session-scoped live map, every participant visible to everyone, with
a runner icon. Phones stay host-only.
