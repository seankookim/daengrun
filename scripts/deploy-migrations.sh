#!/bin/bash
# deploy-migrations.sh — the one sanctioned way to `supabase db push` for this repo.
#
#   bash scripts/deploy-migrations.sh                       # dry-run: shows exactly what WOULD push
#   bash scripts/deploy-migrations.sh --push 0109_revoke_truncate.sql [more.sql…]
#                                                           # pushes ONLY if the pending set == the names you passed
#
# What it enforces (each was a hand-step somebody skipped, or nearly did):
#   1. Deploys come from TRUNK, not from whatever tree you are in — it fetches and cuts a fresh
#      detached worktree at origin/redesign-v4. "Land on trunk BEFORE deploy" becomes structural.
#   2. Every file listed in supabase/migrations/HELD is moved aside BEFORE the CLI sees the tree,
#      so a held migration cannot ship as cargo (2026-08-19: `--include-all` from a tree carrying
#      the held 0105 listed 0105 to push; with it aside the list was empty — measured both ways).
#   3. It always dry-runs first and PRINTS the list. With --push, it refuses unless the dry-run's
#      pending set is exactly the filenames you named. Your expectation is checked by the machine,
#      not by you reading output under time pressure.
#   4. It never runs `supabase migration repair`. If the CLI suggests
#      `migration repair --status reverted …`, that hint is wrong for this repo (it would mark
#      APPLIED migrations reverted); the fix is to be on trunk, which this script guarantees.
#   5. After a push it prints `migration list --linked` so you read back what landed.
#
# It does NOT run the harness or /autoplan — those are gates BEFORE landing on trunk. This script is
# the step after. It uses `--include-all` because with held files aside that flag is what applies a
# lower-numbered file that lands after a higher one (0106 shipped that way); step 3 makes it safe.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
TRUNK="origin/redesign-v4"
HELD_FILE="supabase/migrations/HELD"
MODE="dry"; EXPECT=()
if [ "${1:-}" = "--push" ]; then MODE="push"; shift; EXPECT=("$@"); fi
if [ "$MODE" = "push" ] && [ ${#EXPECT[@]} -eq 0 ]; then
  echo "refusing: --push needs the exact migration filenames you expect to apply" >&2; exit 2
fi

git -C "$REPO" fetch -q origin
TIP="$(git -C "$REPO" rev-parse --short "$TRUNK")"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/daengrun-deploy-XXXXXX")"
DEPLOY="$SCRATCH/tree"; ASIDE="$SCRATCH/held-aside"; mkdir -p "$ASIDE"
cleanup(){ git -C "$REPO" worktree remove --force "$DEPLOY" >/dev/null 2>&1 || true; git -C "$REPO" worktree prune >/dev/null 2>&1 || true; rm -rf "$SCRATCH"; }
trap cleanup EXIT
git -C "$REPO" worktree add -q --detach "$DEPLOY" "$TRUNK"
echo "deploy tree: detached at $TRUNK ($TIP)"

# 2. move HELD files aside
if [ -f "$DEPLOY/$HELD_FILE" ]; then
  while IFS= read -r line; do
    f="${line%%#*}"; f="$(echo "$f" | tr -d '[:space:]')"; [ -z "$f" ] && continue
    if [ -f "$DEPLOY/supabase/migrations/$f" ]; then
      mv "$DEPLOY/supabase/migrations/$f" "$ASIDE/"; echo "held aside: $f"
    else
      echo "warning: HELD names $f but trunk has no such file (stale line?)" >&2
    fi
  done < "$DEPLOY/$HELD_FILE"
fi
for e in "${EXPECT[@]:-}"; do
  [ -z "$e" ] && continue
  if [ -f "$ASIDE/$e" ]; then echo "refusing: $e is HELD — remove it from $HELD_FILE in the commit that lands it, with a REGISTRY row saying why" >&2; exit 3; fi
done

# 3. dry-run and read the list by machine
cd "$DEPLOY"
DRY="$(supabase db push --linked --include-all --dry-run 2>&1 | tr -d '\r')"
PENDING="$(echo "$DRY" | grep -E '^[[:space:]]*•[[:space:]]' | sed -E 's/^[[:space:]]*•[[:space:]]*//' | sort || true)"
echo "── dry-run ──"; echo "$DRY" | grep -vE '^(Initialising|Connecting|Skipping migration)' || true
if [ -z "$PENDING" ]; then echo "pending set: (empty — remote is up to date with trunk minus HELD)"; else echo "pending set:"; echo "$PENDING" | sed 's/^/  /'; fi
[ "$MODE" = "dry" ] && { echo "dry-run only. To apply: bash scripts/deploy-migrations.sh --push <exact filenames above>"; exit 0; }

WANT="$(printf '%s\n' "${EXPECT[@]}" | sort)"
if [ "$PENDING" != "$WANT" ]; then
  echo "refusing: pending set differs from what you named." >&2
  echo "  named:   $(echo "$WANT" | tr '\n' ' ')" >&2
  echo "  pending: $(echo "${PENDING:-<none>}" | tr '\n' ' ')" >&2
  echo "  Either trunk is missing your file (land it first) or something you did not name would ship. Nothing was pushed." >&2
  exit 4
fi

echo "── pushing exactly: $(echo "$WANT" | tr '\n' ' ')──"
supabase db push --linked --include-all
echo "── read back ──"
supabase migration list --linked 2>/dev/null | tail -c 400 | tr ',' '\n' | grep -E '"local":"01[0-9]{2}"' | tail -8 || supabase migration list --linked | tail -12
echo "done. Now verify the change live (an attack rolled back / an over-the-wire read as anon) and record it in REGISTRY.md."
