# Guest GPS — what is true, and the one question only Sean can answer

**Written 2026-08-27 by a read-only scout.** Every citation below was re-read at source in this
tree at write time (`e3f5a63`), not carried from the handoff.

**Epistemic labels, per CLAUDE.md.** Everything in this document is **READ** — source files in this
worktree. Nothing is **OBSERVED**: no query was run against production, no harness, no device. Where
I say "the server refuses X", the rung is *the deployed migration file says so*, not *I watched it
refuse*. Production being at `0152` (so `0146` is live) is READ from `docs/session-handoff.md`, which
is a document, not an artifact — treat it as the weakest claim here.

---

## (a) What is true today

### 1. There is no "pack GPS". There is one owner watching one runner.

The live-location product is **one channel per BOOKING**, and it carries exactly one worker's
position to exactly one customer.

| | |
|---|---|
| topic name | `run2-<bookingId>` — `app/src/lib/geo.ts:375` |
| who publishes | the assigned runner, `app/src/lib/geo.ts:409-431` (1:1) and `:467-489` (club, one publisher fanning out to N booking topics) |
| who subscribes | the owner, on `app/app/owner/live.tsx:237`, for one `bookingId` |
| server rule | `run_channel_allowed` — `read` iff `uid = owner_id or uid = runner_id`; `write` iff `uid = runner_id`; **and only while `status in ('runner_enroute','picked_up','active')`** — `supabase/migrations/0104_run_channel_namespace_v2.sql:46,63-71` |
| how it is enforced | `realtime.messages` RLS, `supabase/migrations/0108_realtime_chat_bk_policies.sql:186-217`. The channel is joined `private:true` (`app/src/lib/geo.ts:364`); a private join is admitted only if the policy returns a row |

Consequences that nobody has written down before, all four verified here:

- **The host sees nobody.** `app/app/club/console/[sid].tsx` renders no map (grep for
  `NaverMapView`: the only club-side map is `app/app/club/run/[sid].tsx:400`, the runner's own).
- **An owner of a delegated dog sees exactly one runner** — their own dog's — via the
  `실시간 지켜보기 →` button, `app/app/club/session/[sid].tsx:1104-1108`.
- **A 동반 owner (has a dog, walks it themselves) neither publishes nor is watchable.**
  `app/app/club/companion/[sid].tsx` imports `startTracking` and **no publisher at all**
  (`:7`, `:141`). Their GPS is recorded locally and saved as a distance; it is never shared with
  anyone, live.
- **The club runner publishes only for dogs they are handling, while the booking is `active`** —
  `app/app/club/run/[sid].tsx:128-129`, `:161`.

So the thing a guest would receive "the same" of is: *an owner watching the runner who is holding
their own dog.* **A guest has no dog, so there is nothing for "the same" to refer to.** This is not
a missing wire — it is a missing product.

### 2. A person-only member is a first-class participant with no booking

`session_rsvp(p_session, p_dog := null)` inserts a `session_people` row and **nothing else** —
no `session_dogs` row, no booking, no money
(`supabase/migrations/0134_club_rsvp_hardening.sql:112-131`). Their role is `owner_attending`
(or `runner_attending` if they are a non-applicant runner) — `:112-114`. **There is no `guest`
role**: the CHECK is a four-value allow-list, `supabase/migrations/0030_hi_club.sql:71`.

They can: see the session, join chat, check in, appear on the roster, be counted in capacity.
They cannot: be watched, watch anyone, or record their own walk.

### 3. Their own walk is refused, by name

`session_record_companion_run` requires a live `owner_handled` dog of theirs in the session and
raises `no_companion_dog` otherwise — `supabase/migrations/0146_companion_run_record.sql:154-162`.
The file's own header names the intended target: `:104` says this token "refuses a purely DELEGATED
owner **and the dogless crew**". `participant_activities.dog_id` **is nullable**
(`supabase/migrations/0030_hi_club.sql:104`), so the table already admits a dogless record; the
function is the only thing refusing it.

### 4. The copy is honest — deliberately, and with the reasoning on the page

`app/app/club/[id].tsx:518-531` promises exactly three things and no more: guests are free, a guest
uses their own account, one person takes one seat. Directly above it, `:507-513` is a 🔴 comment
saying GPS is deliberately **not** claimed, citing the same `geo.ts:375` and `0146:162` facts.
**Nothing in the product tells a user they will get a live map.** There is no lie to fix.

### 5. Two facts that decide the privacy answer

**(i) Session membership is self-serve.** `club_sessions` is `select using (true)` — readable by
anon (`supabase/migrations/0030_hi_club.sql:133`). `session_people` is readable by **every
signed-in user** (`0030:135`). `session_rsvp` gates on session open / seats left / your own dog, and
**on nothing else** — no club membership, no host approval (`0134:53-61`). So *"a member of this
session"* means *"any signed-in person who found an open session and tapped join."*

**(ii) The drafted privacy policy already answers the disclosure question, in the opposite
direction.** `docs/legal/privacy-policy.md:88-91`, verbatim:

> **수집 시점**: 러닝이 시작된 시점부터 종료 시점까지만 수집합니다.
> **제공 대상**: 해당 예약의 보호자에게만 제공됩니다. 다른 이용자나 제3자에게 제공하지 않습니다.

*Provided to the owner of that booking only. Not to other users or third parties.* Every option
below that shows a runner's position to a non-owner **requires that sentence to be rewritten**, and
that document is currently sitting in front of counsel (open queue item #1;
`docs/biz/location-law-counsel-brief.md:91` confirms it is an unpublished draft). This is the single
most decision-relevant fact in this file and it is not mentioned anywhere in the handoff.

### 6. The plumbing is closer than "needs a session-scoped channel" suggests

A session-scoped realtime family **already exists and is already gated**: `club-chat-<sessionId>`,
admitted to anyone with `_club_shell_access(session, uid) <> 'none'`
(`supabase/migrations/0108_realtime_chat_bk_policies.sql:108-110,137-140`; the grader is
`supabase/migrations/0049_session_shell.sql:9-25`, grades `host` / `full` / `limited` / `none`).
What does **not** exist is a **broadcast WRITE policy**: `channel_allowed` returns false for `write`
on every non-`run2` family (`0108:125`), and the INSERT policy is additionally fenced to
`realtime.topic() like 'run2-%'` (`0108:212-216`). So the work is "one new family + one write
predicate + a live window", not "build a channel layer".

---

## (b) Where the handoff was right, and where it was wrong

| handoff claim | verdict |
|---|---|
| live share is per-BOOKING, `geo.ts:375/441/467` | **RIGHT**, exact line numbers |
| a person-only member has no booking | **RIGHT** (`0134:112-131`) |
| own walk refused — `0146:162` `no_companion_dog`, `0146:104` names the dogless crew | **RIGHT**, exact |
| the board copy claims nothing about GPS, so it is honest | **RIGHT** (`app/app/club/[id].tsx:507-531`) |
| "closing it needs a session-scoped channel plus a server decision on who may watch" | **INCOMPLETE — three ways** |

⚠ A note on where those four right answers came from: `app/app/club/[id].tsx:507-513` already
carries the same three citations in a source comment. The handoff's "Measured" is very likely a
re-reading of that comment rather than an independent measurement. It happens to be correct — I
re-derived each one at source — but a reader should not treat handoff and comment as two
confirmations. *Agreement between two records of the same read is the same claim counted twice.*

**① It is framed as a guest gap. It is a pack gap.** A 동반 owner with a dog is equally invisible
and equally blind (`app/app/club/companion/[sid].tsx` has no publisher). The host — the person Sean
said should be *"running with the pack leading the way"* — sees nothing at all. Building a
guest-only feature would be building the narrow version of a thing that is missing for everyone.

**② "Half a ruling of his is unbuilt" overstates what he ruled.** The source
(`docs/decisions/2026-08-25-console-rulings.md:1271-1280`) records his four sentences as *ruled in
direction*; `:1302-1306` records, in that same document and at the same time, that **the direction
of sharing and who may see whom was explicitly left unsettled** — flagged then as "a privacy
surface". So nothing is owed to him yet. The correct sentence is: *he ruled a benefit; the shape of
the disclosure was never asked and is still not asked.* This file asks it.

**③ It omits the constraint that decides the answer** — the privacy policy's
「해당 예약의 보호자에게만」 (§a.5.ii). Any option that widens the audience is a legal-document
change on a document already with counsel.

One correction that cuts the other way, so the handoff is not left looking worse than it is: it says
closing this "needs a session-scoped channel". A session-scoped **read** gate already exists and is
already pinned; the missing piece is narrower than that sentence implies (§a.6).

---

## (c) The options

Cost bands are my estimate from the code read, not measured.

| | **A — Guest watches the pack** | **B — Everyone shares with everyone** | **C — Record, not map** |
|---|---|---|---|
| **What the guest gets** | A live map of the session: the runners' positions while they are running. Sees; is not seen. | A live map, **and their own dot is on it** for every other member. Sean's words at their fullest. | No live map. They get a walk record (distance, time, 도장) and the session's own screens. |
| **Who can see whose location** | Every session member sees **every working runner**. Guests' and owners' own locations stay private. | Every session member sees **every other member**, including private individuals who are not working. | Unchanged from today: one owner ↔ their own dog's runner. |
| **Server work** | New `pack-<sessionId>` broadcast family in `channel_allowed`: read = the chosen rule (below), write = a committed/handling runner of that session. Needs a **live window** — a session has no equivalent of `runner_enroute/picked_up/active`; `status in ('open','full')` plus a clock around `scheduled_at` is the honest substitute. | Everything in A, **plus** write admitted to any checked-in member, plus a per-person opt-out that actually gates the publisher. | One predicate in `session_record_companion_run` (allow `v_dog is null` for a checked-in dogless member; `dog_id` is already nullable) + its pins. No realtime work at all. |
| **Client work** | New pack-map screen + one extra topic on the club-run publisher (`app/app/club/run/[sid].tsx:161`). | A + a publisher on `app/app/club/companion/[sid].tsx` + a guest run screen (does not exist) + opt-out UI. | A CTA for dogless members on `app/app/club/session/[sid].tsx` (b6's open item) reusing `app/app/club/companion/[sid].tsx`. |
| **Privacy policy** | 「제공 대상: 해당 예약의 보호자에게만」 must be rewritten before ship. | Same rewrite, **wider** — a new category: a non-worker's real-time location shown to self-selected strangers. Plus a new lawful basis and a consent gate; counsel-shaped. | **No change.** Location collection and disclosure are untouched. |
| **Risk** | Medium. Any signed-in person can RSVP into an open session (§a.5.i) and then watch every runner working it. | High. The same self-serve door, now pointed at private individuals' live positions. This is the shape a stalking complaint takes. | Low. Closes the smaller, uncontested half of his sentence and adds no disclosure. |
| **Honest headline** | "Guests can watch the walk." | "Guests are on the map." | "Guests get credit for the walk." |

**A and C are not exclusive** — C is cheap, safe, and can ship now regardless of which way A/B goes.

### The "who may watch" rule — the part only Sean can rule on

Whatever the direction, someone must be named. These are the candidates the code can actually
express today, widest to strictest:

| candidate rule | expressed as | what it exposes |
|---|---|---|
| **anyone with the club board open** | no gate | Anyone, signed in or not, watching a live walk. `club_sessions` is anon-readable, so this is effectively public. Listed for completeness; I would not put it forward as viable. |
| **anyone who joined this session** | `_club_shell_access(sid, uid) <> 'none'` | Includes `limited` — someone whose delegation was *rejected or withdrawn* (`0049:21-22`). Widest defensible option, and still self-serve (§a.5.i). |
| **people actually attending** | `_club_shell_access in ('host','full')` | RSVP'd members + committed runners + approved delegating owners. Still admits an RSVP who never showed up. |
| **people who checked in** | `session_people.checked_in_at is not null` | Physically present at the meetup. Same conjunct `0146` already chose (`0146:141`, and its header at `:110-123` argues for exactly this shape). **Narrowest that still delivers the feature**, and the only one that resists a stranger walking in. |
| **only the host** | `club_sessions.host_profile_id` / `backup_host_profile_id` | A safety console, not a shared benefit. Does not deliver his sentence. |

My read, offered as a read and not as something to bank: **checked-in** is the only rule that
survives the fact that anyone can join an open session, and it costs nothing extra because `0146`
already established the same predicate for the same reason.

---

## (d) Flagged hazards

1. 🔴 **Self-serve membership is the whole problem.** Nobody approves an RSVP. A location channel
   scoped to "session members" is scoped to "whoever wanted in", and the widening is invisible in
   the code — it reads as a membership check.
2. 🔴 **A person's live location is a different category from a worker's.** Everything shipped so
   far discloses a *runner's* position, *while working*, *to the customer paying for that work*,
   and the privacy policy says so in one sentence. Option B leaves that category entirely.
3. 🔴 **A session has no "live" window.** A booking's status machine closes the channel by itself
   (`0104:46`). A session's does not — `status = 'open'` is true for days beforehand. Without an
   explicit window, a session channel is a location feed that opens the moment the session is
   created. This is the CLAUDE.md §Migrations "attack INACTION" case: the failure arrives when
   nobody does anything.
4. ⚠ **Guests and the host's phone list interact, and that is true today.**
   `phone-host-scope = wide` was ruled — the host sees every member's number
   (`supabase/migrations/0053_audit_followups.sql:412-444`, which also writes an access-log row).
   Whether a guest is a "member" for that rule was flagged open on 2026-08-26 and is still open.
   **Bringing a friend currently hands the host their phone number**, with no GPS involved. It
   deserves its own line in Sean's queue.
5. ⚠ **The privacy policy is with counsel right now.** If any GPS widening is going to happen, the
   amendment belongs in the same envelope rather than as a second letter.

---

## (e) THE QUESTION FOR SEAN

*Context in one line: right now the only live map in the app shows one dog's walker to that one
dog's owner. There is no map of the group — the host cannot see the pack either. So "the same GPS
share" has nothing yet to be the same as.*

> **When someone comes to a club walk without a dog, what should they see on their phone during
> the walk?**
>
> **1 — Nothing live, but they get credit.** No map. When the walk ends they get a record of it:
> distance, time, the stamp — same as everyone else who walked. *Cheap, ships this week, changes
> no privacy promise.*
>
> **2 — They can watch the walk.** A live map of where the walkers are. They can see; nobody can
> see them. *Needs the privacy policy changed — it currently promises a walker's location goes to
> that dog's owner and to no one else. Add it to the lawyer's envelope.*
>
> **3 — Everyone is on the map, including them.** Everyone at the walk sees everyone else's dot,
> live. *The fullest version of what you said. It also means a stranger who taps 참가 on an open
> session can watch a real person move around Banpo in real time, because nobody approves who
> joins. This one needs the lawyer's answer before it is built, not after.*
>
> **And if you pick 2 or 3 — who exactly is allowed to look?**
>
> **(a)** anyone who joined the session · **(b)** only people who actually checked in at the
> meetup · **(c)** only the host.
>
> *(Today anyone can join an open session with one tap — no approval. So (a) means "anyone who
> wants to". (b) means they had to show up in person.)*

1 and 2 can both be true — 1 does not block 2. My read is that **1 now, and 2 or 3 only after
counsel answers**, is the honest order: option 1 is the half of his sentence that costs nothing to
keep, and the board currently promises neither.
