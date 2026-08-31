# Setting up daengrun on a new Mac — written 2026-08-28, every step verified on the old machine

One clone command gets you the code; this file is IN the repo so it arrives with it. Everything
below is split by what git carries for you versus what only you can supply. Times assume a fresh
macOS with Homebrew.

> **2026-08-31 update:** the repo is now PUBLIC (free CI; secrets sweep was clean — only
> designed-public EXPO_PUBLIC values were ever committed). Cloning works over HTTPS without any
> key; the SSH key is still needed to PUSH. **Session bootstrap on the new Mac:** open three
> Claude chats and give each one line — 「Read docs/prompts/master-announcer.md fully and begin.」
> / 「Read docs/prompts/master-backend.md fully and begin.」 / 「Read docs/prompts/master-ui.md
> fully and begin.」 (announcer first). Unlanded old-Mac work is snapshotted on
> `rescue/wip-*-2026-08-31` branches (b1-pack-publish · 0157-adopted · 0158-adopted ·
> ui-round3); the prompts tell each session how to adopt them. The §"before retiring the old
> machine" sweep below still applies before any wipe.

## 0. What git already carries (nothing to do)

- **The default branch is `redesign-v4` and `main` is deleted**, so a fresh clone lands on the
  right branch by construction. ⚠ The `git remote set-head` repair in CLAUDE.md is for clones
  that PREDATE the default-branch change — a new clone does not need it and running it is harmless.
- `supabase/.temp/linked-project.json` is **tracked**, so the Supabase project link travels —
  `supabase` CLI commands find the right project once you log in.
- `app/eas.json` with all four build profiles (including the `simulator` profile that produced
  the first working build), `app/.env.example` (the shape of the env file, not the values),
  the pre-push hook source in `.githooks/`, and every test/gate script.

## 1. Clone and wire the hook (2 min)

```bash
git clone git@github.com:seankookim/daengrun.git ~/dev/daengrun
cd ~/dev/daengrun
git config --local core.hooksPath "$HOME/dev/daengrun/.githooks"
```

⚠ **Two laws about that hook, both paid for:**
- **Committing the hook does not install it** — the `git config` line above is the installation,
  and it is per-clone. Verify it took: `git config --get core.hooksPath` must print the path.
- Point it at the **clone's own stable path**, never `$(git rev-parse --show-toplevel)` — inside a
  worktree that resolves to the worktree, worktrees are disposable, and git runs NO hooks and says
  NOTHING when hooksPath names a vanished directory.
- The hook uses `/usr/bin/grep` semantics. If your shell wraps `grep` (this repo's old machine
  execs `ugrep`), test anything hook-related with the absolute path `/usr/bin/grep`.

Keep the path `~/dev/daengrun` if you want Claude sessions' project identity (and any copied
memory, §7) to line up with the old machine.

## 2. The app (10 min + downloads)

```bash
cd ~/dev/daengrun/app
npm install
```

**`.env` is gitignored and required** — without it the app cannot reach Supabase. Two ways to get
it, in order of preference:

1. **Pull it from EAS** (the values were pushed to the `preview` environment on 2026-08-27):
   ```bash
   npm i -g eas-cli
   eas login          # your Expo account
   eas env:pull --environment preview --path .env
   ```
2. Or copy `app/.env` from the old Mac (it is ~300 bytes, two `EXPO_PUBLIC_*` lines matching
   `.env.example`).

Then prove the toolchain end to end without any device:

```bash
npm test             # expect several suites; count '^PASS' across the WHOLE output — never tail.
                     # 797 PASS / 0 FAIL as of 2026-08-28. The last suite alone prints ~10.
./node_modules/.bin/tsc --noEmit
npx expo export      # bundles clean in ~1 min if .env and deps are right
```

## 3. iOS (the long pole — Xcode download dominates)

`app/ios/` is **gitignored** (1.2 GB of pods and build products) — you regenerate it, not copy it:

```bash
# after installing Xcode from the App Store and running it once
sudo xcodebuild -license accept
xcodebuild -downloadPlatform iOS
cd ~/dev/daengrun/app
npx expo prebuild -p ios     # regenerates ios/ from app.json
cd ios && pod install
```

**The build that actually works is the LOCAL simulator build** — three EAS cloud builds died at
the `Configure expo-updates` phase and the local route skips it entirely, needs no Apple signing,
and produced the first-ever running build on 2026-08-28:

```bash
cd ~/dev/daengrun/app/ios
xcodebuild -workspace app.xcworkspace -scheme app -configuration Release \
  -sdk iphonesimulator -destination "generic/platform=iOS Simulator" \
  -derivedDataPath /tmp/dd CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
xcrun simctl install booted /tmp/dd/Build/Products/Release-iphonesimulator/app.app
xcrun simctl launch booted com.seankookim.daengrun
```

⚠ A **Debug** build from a worktree silently loads a peer session's Metro bundle — build
**Release** and, if in doubt, prove a fresh literal is inside the Hermes `main.jsbundle`
(ASCII identifiers only; Korean strings are stored UTF-16 and a plain grep misses them).

## 4. The SQL harness (5 min)

```bash
brew install postgresql@16
cd ~/dev/daengrun/supabase/tests
PATH="/opt/homebrew/opt/postgresql@16/bin:$PATH" LC_ALL=C bash harness.sh
```

Expect **1135 pass / 0 fail** as of 2026-08-28 (the number only grows). `pg_ctl` must start in the
same shell invocation; the harness runs fine from worktrees. ⚠ When a scratch harness is done,
stop its cluster — 9+ stale postmasters once exhausted shared memory and made every battery,
including the control, fail in a way that read as success.

## 5. Supabase CLI (deploy path — the link travels, the login doesn't)

```bash
brew install supabase/tap/supabase
supabase login        # your access token — the one thing git cannot carry
supabase migration list --linked   # should show local == remote with nothing pending
```

`db push` / `functions deploy` conditions in CLAUDE.md §Operations apply unchanged: gates green
first, never from a worktree carrying an unfinished migration, verify after by reading back.

## 6. Review tooling

```bash
npm i -g @openai/codex     # 0.147.0 on the old machine; needs your OpenAI login
```

The codex invocation and its many measured traps are in CLAUDE.md — read that section before the
first run; every rule in it was paid for.

## 7. Claude Code environment (optional but recommended)

- Global instructions: copy `~/.claude/CLAUDE.md` from the old Mac (gstack routing lives there).
- gstack skills: `git clone https://github.com/garrytan/gstack.git ~/.claude/skills/gstack &&
  cd ~/.claude/skills/gstack && ./setup` (needs bun).
- Session memory: copy `~/.claude/projects/-Users-sean-dev-daengrun/` from the old Mac if you want
  continuity — it is path-keyed, which is why §1 suggests keeping `~/dev/daengrun`.

## 8. Credentials that only you hold (git carries none of these)

| Credential | Needed for |
|---|---|
| GitHub SSH key | clone + push |
| Expo/EAS login | `.env` pull, any cloud build |
| Apple ID (interactive 2FA) | any SIGNED build — simulator builds need none |
| Supabase access token | deploys, `db query --linked` |
| OpenAI login | codex reviews |
| Toss / PG, 사업자등록, APNs `.p8` | money go-live — not needed for development |

## ⚠ Before retiring or wiping the OLD machine — and only then

A clone gets you everything **landed**. It cannot get you work that is mid-flight in another
session's tree. On 2026-08-28 at write time, three trees on the old machine held uncommitted
in-flight work (a chat/messages client slice in the main clone; the 0157 and 0158 codex-fix
migrations in two agent worktrees). If both Macs stay alive this is irrelevant — the sessions land
their own work. If you ever wipe the old machine, run this there first and let anything dirty land:

```bash
cd ~/dev/daengrun && git worktree list --porcelain | grep '^worktree ' | cut -d' ' -f2 | \
  while read w; do n=$(git -C "$w" status --porcelain 2>/dev/null | wc -l); \
  [ "$n" -gt 0 ] && echo "$n dirty: $w"; done
```
