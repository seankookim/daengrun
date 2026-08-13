# ⑬ Runner↔owner chat does not reach a phone — and ⑪/⑫ both depend on it

**Status: ✅ BUILT 2026-08-13 — `0090_chat_notify.sql` + suite `126`. Harness 510/0, deno 185/0,
five mutations verified.** ⑪ and ⑫ are unblocked on this axis.

**What shipped:** a trigger on `chat_messages` writes the other party a `notifications` row,
which 0024's existing trigger turns into a push.
· **No message text in the push** (who + which run only) — 0024 pushes bodies verbatim to a
  lock screen, and during an incident that phone is the one most likely to be handed around.
· **One nudge per unread state** — while the first is unread, further messages write nothing;
  reading it re-arms. A back-and-forth is one push; nobody-is-reading keeps its one signal.
· The title is a **routing key** (a tap opens `/chat`), pinned both directions by
  `_test/chat_notify_contract_test.ts`, which reads the migration at test time.
· **An existing pin caught a real defect in the first draft:** the trigger function was left
  `anon`-executable and 99's S1 definer sweep went red. Revoked.

**Two product calls remain Sean's** (bottom of this memo) — neither blocks anything.

*Original writeup:* No decision needed to start; it is a
gap between what the product implies and what the code does.

## The gap, verified on trunk

| fact | evidence |
|---|---|
| Push fires on **one** thing only | `0024_push.sql:43-44` — `create trigger notifications_push after insert on notifications` |
| There is **no trigger on `chat_messages`** | checked every migration; none exists |
| Sending a chat writes **only** the message | `api.ts:2325-2331` — `sendChatMessage` inserts into `chat_messages` and returns; no `notifications` row |
| Chat is realtime **in-app only** | `api.ts:2353` — a realtime subscription on `chat_messages`, which delivers to an open screen |

**So a chat message is visible if the other person happens to have that screen open, and silent
otherwise.** The phone in a pocket never rings.

**The nuance that makes this precise:** it is not that nothing notifies. *Structured events* do
— the owner's stop request writes a `notifications` row (`notifyRunStop`, `api.ts:2476`), which
is why the stop sheet can honestly say "알림으로 보내고 채팅에도 남겨요". It is **free-form chat
between the two parties** that has no path to a phone. The channel people reach for when
something unexpected happens is the one that doesn't ring.

## Why it blocks ⑪ and ⑫

**⑫**: every one of Sean's four rulings is *tell someone something* — tell the runner pay waits
for return, tell the owner where the relief point is, make custody legible. And his design gate
is *"we dont want the runner stranded in the middle of town."* Today a runner standing in the
street with an unreturned dog can message the owner and **the owner's phone stays silent**,
while the 2h clock runs toward a state neither of them can exit. The escalation is not the
first failure in that story; the unanswered message is.

**⑪**: two-sided incident verification requires reaching the second side. A confirmation request
that arrives only if the other party already has the app open is not a verification mechanism —
it is a verification mechanism *for people who happen to be looking*. The phone-number ruling
(⑪'s emergency-scoped contact) exists precisely because the parties need to reach each other in
an emergency; a chat that doesn't ring is why that ruling was needed, and fixing chat does not
remove the need — it lowers how often the fallback is the only option.

## Build notes

- **The mechanism already exists and is proven** — a `notifications` insert is the push path,
  it's the same one `notifyRunStop` uses. This is wiring, not new infrastructure.
- **Do NOT put the message body in the push body without deciding that deliberately.** 0024
  pushes `title`/`body` **verbatim to a lock screen** (that is how the ops-alert leak happened,
  and why ops payloads are now redacted). A chat push should probably name the sender and the
  booking, not carry the message text — but that is a product call, and it is a small one worth
  making explicitly rather than by copying the existing pattern.
- **Rate/collapse it.** One push per message turns a normal back-and-forth into a notification
  storm; the existing `notifications` table has no dedupe. Whoever builds this decides whether
  it's per-message, per-thread-per-N-minutes, or first-unread-only.
- **Don't notify the sender.** Obvious, and exactly the kind of thing a trigger gets wrong.
- **Where it goes:** a trigger on `chat_messages` mirroring 0024's shape is the cheap version;
  doing it in `sendChatMessage` would miss `sendChatPhoto` and anything else that inserts.
  A trigger is the honest place, for the same reason the push trigger lives on `notifications`.
- **Suite it:** a pin that a chat insert produces exactly one notification for the *other*
  party and zero for the sender. The harness stubs `net.http_post`, so this is observable
  (`00_shim.sql`).

## Not decided here

Whether chat push carries the message text, and the collapse policy. Both are small product
calls for Sean; neither blocks starting the trigger.
