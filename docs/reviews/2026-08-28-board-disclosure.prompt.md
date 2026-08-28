You are a cold reviewer. You have no author reasoning to lean on. Read the code, not the comments.
In this repo `prosrc` carries our own prose inside it, and a comment quoting removed code has
repeatedly defeated greps in both directions. Cite executable lines only.

# System

daengrun (도그스하이) — a Korean dog-running marketplace. React Native/Expo client, Supabase
(Postgres + edge functions). Pre-launch, Banpo pilot. All three migrations below are LIVE in
production (production is at 0152, nothing pending).

This is a PRIVACY / DISCLOSURE review. The product handles real people's names, photos, profiles,
home neighbourhoods and — in a separate family — phone numbers. Nothing here is gated behind a
money flag, so **everything you find is reachable today** by any signed-in user.

# The slice under review — the club session board and the RLS policy that trusts it

Read as ONE chain, in order. This repo uses `create or replace` heavily and one of these files
DROPS and recreates a function, so reading any one alone reviews the wrong body:

  supabase/migrations/0136_club_session_board.sql
      creates `club_session_board`.
  supabase/migrations/0139_board_profile_ids.sql
      DROPS and recreates `club_session_board` to add `owner_profile_id` / `runner_profile_id`,
      explicitly reversing 0136's own contract decision (0136 §4 R8). Grants are restated.
  supabase/migrations/0145_profile_card_board_peer.sql
      adds an RLS policy on `profiles` whose predicate is `_profile_board_visible`, and that
      helper **delegates its authority to whatever `club_session_board` currently is.**

Also read, because they define who counts as a member/party:
  supabase/migrations/0131_scope_open_read_policies.sql   (`_club_session_member`, the re-scoped
                                                           read policies; 7 review rounds, but they
                                                           covered 0131 ALONE — the interaction
                                                           with 0145/0146 has never been reviewed)
  supabase/migrations/0030_hi_club.sql                    (clubs, club_members, club_sessions)

The client half — review it too, since a server-only pass misses the pairing:
  app/src/lib/api.ts                       (the `club_session_board` call and its projection,
                                            incl. `ownerProfileId` / `runnerProfileId`)
  app/src/components/club-board.tsx        (the tap that routes to a profile)
  app/app/runner-profile/[id].tsx          (the destination)
  app/app/club/[id].tsx                    (the board's viewer gate)

# House laws — violations are findings

1. **Party gate before state gate.** Flat whitelisted returns; never `select *`.
2. A SECURITY DEFINER function MUST set `search_path` in the BODY. A `create or replace` in a file
   that did not first define the function, without a same-file ACL, is a latent PUBLIC-EXECUTE
   hole — and note that 0139 DROPS the function, which discards its ACL entirely, so 0139 owes a
   complete re-grant.
3. **Presence of `auth.uid()` in a predicate does not mean GATED BY `auth.uid()`.** This repo has
   already shipped a policy where the caller term sat in ONE ARM OF AN OR, so the other disjunct
   matched for everyone. Check every policy for that shape specifically.
4. A finding's SENTENCE is the property; the site someone cited is one place it is observable.
   Enumerate every site the property covers.

# What to hunt, in priority order

A. 🔴 **The redaction pairing.** 0139 adds profile IDs beside names that 0136 was deliberately
   redacting in some states (a courtship / pick-pending runner whose NAME is NULL). **An id that
   survives where the name is redacted re-identifies the person the redaction was protecting.**
   Enumerate every state the board can return, and for each say whether name and id are redacted
   TOGETHER. Any state where the name is NULL and the id is not is a CRITICAL finding.

B. 🔴 **The delegated-authority chain.** `_profile_board_visible` decides a `profiles` RLS policy by
   asking `club_session_board`. Establish exactly: whose rows does that admit, under what caller,
   and can a caller influence the arguments to widen it? Because a `profiles` policy inherits this,
   **one board leak becomes a general read of other people's profile rows** — say precisely which
   profile columns become readable and to whom. Check the SECURITY DEFINER / INVOKER status of every
   link in the chain, since a definer in the middle changes whose privileges apply.

C. **Who is a "member".** `session_rsvp` has no club-membership gate and no host approval, and
   `club_sessions` is readable broadly — so "a member of this session" may mean "anyone who found an
   open session and tapped join", while READING like a membership check. Say whether the board and
   the profiles policy are gated on something a stranger can grant themselves.

D. **0139's DROP.** Confirm the recreated function's ACL, owner, `prosecdef` and in-body
   `search_path` are all restated. A DROP discards grants; a later `create or replace` elsewhere
   would then be a plain CREATE, which is born PUBLIC-executable.

E. **Inaction, not only transitions.** A session that ends, is abandoned, or that nobody transitions
   out of — does board visibility (and therefore profile visibility) ever CLOSE? A grant justified
   as "it closes when X happens" is a finding if X can simply never happen.

F. **The client half.** Does the client render or route on an id it should not have? Is any profile
   id present in a payload for a person whose name is deliberately hidden on screen?

# What I do NOT want

- Style, naming or formatting opinions.
- Findings whose only evidence is a comment.
- Speculation you did not check in source. Put unsettled things under OPEN QUESTIONS.

# Output format

Per finding: one-line title · severity CRITICAL/HIGH/MEDIUM/LOW · `file:line` citations of
executable lines · the concrete failure scenario (who can see whose data, and by what call) ·
the smallest fix.

Then OPEN QUESTIONS.

End your response with exactly these two lines, in this order and nothing after them:

FINDINGS: <n>
VERDICT: <verdict>

where <n> is the integer count of findings you reported, and <verdict> is whichever one of these
three is right: approve; approve-with-fixes; reject. Write it in capitals.
