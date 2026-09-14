#!/bin/bash
# codex runner — one invocation shape for every Claude→Codex call in this repo.
#
#   scripts/codex/run.sh <name> <mode> <model> <effort> <workdir> <prompt-file>
#
#   mode    review | write
#           review = --sandbox read-only            (codex may only read; verdicts, audits)
#           write  = --sandbox workspace-write      (codex edits files inside <workdir> only)
#   model   gpt-5.6-sol | gpt-6-astra
#   effort  low | medium | high | xhigh
#
# Outputs, all under $CODEX_OUT (default docs/reviews/.codex-runs/, gitignored):
#   <name>.out     stdout  — the ANSWER only (final message)
#   <name>.err     stderr  — the prompt echo + the reading transcript (liveness signal)
#   <name>.last    the final message alone (codex -o), the artifact to copy into a ledger
#   <name>.status  three-state result, see below
#
# Laws this encodes (CLAUDE.md §codex, all measured):
#   * streams are captured SEPARATELY — the prompt is echoed on stderr, so any grep of a
#     merged log matches your own question.
#   * a run is DONE when a value only codex can produce is in <name>.out:
#     `^FINDINGS: [0-9]+` for reviews, `^CHANGED: [0-9]+` for write runs. The prompt must
#     carry the placeholder form (`FINDINGS: <n>`), never a digit.
#   * failure states are enumerated, not inferred from exit code or log size:
#     usage-limit wall · untrusted-directory refusal · process gone with no verdict.
#   * `< /dev/null` so codex never waits on stdin.
set -u
name=$1; mode=$2; model=$3; effort=$4; wd=$5; pf=$6
CODEX_BIN=${CODEX_BIN:-$(command -v codex || echo /Applications/ChatGPT.app/Contents/Resources/codex)}
OUT=${CODEX_OUT:-$(git -C "$wd" rev-parse --show-toplevel 2>/dev/null || echo .)/docs/reviews/.codex-runs}
mkdir -p "$OUT"
case "$mode" in
  review) sb=read-only; detector='^FINDINGS: [0-9]+' ;;
  write)  sb=workspace-write; detector='^CHANGED: [0-9]+' ;;
  *) echo "mode must be review|write" >&2; exit 2 ;;
esac
if [ ! -d "$wd/.git" ] && ! git -C "$wd" rev-parse --git-dir >/dev/null 2>&1; then
  echo "REFUSED: $wd is not a git repo (codex will not read it; git init a frozen export)" >&2; exit 3
fi
if grep -qE '^(FINDINGS|CHANGED): [0-9]' "$pf"; then
  echo "REFUSED: prompt contains a literal digit after FINDINGS:/CHANGED: — the detector would match the echo" >&2; exit 4
fi
"$CODEX_BIN" exec --sandbox "$sb" -C "$wd" -m "$model" -c model_reasoning_effort="$effort" \
  -o "$OUT/$name.last" "$(cat "$pf")" < /dev/null > "$OUT/$name.out" 2> "$OUT/$name.err"
rc=$?
hits=$(grep -cE "$detector" "$OUT/$name.out")
wall=$(tail -30 "$OUT/$name.err" | grep -ci 'usage limit')
untrusted=$(tail -30 "$OUT/$name.err" | grep -ci 'not inside a trusted directory')
if [ "$hits" -ge 1 ]; then state=ANSWERED
elif [ "$wall" -ge 1 ]; then state=QUOTA_WALL
elif [ "$untrusted" -ge 1 ]; then state=REFUSED_UNTRUSTED
else state=NO_VERDICT; fi
{
  echo "state=$state"; echo "exit=$rc"; echo "detector_hits=$hits"
  echo "model=$model effort=$effort mode=$mode workdir=$wd"
  echo "out_bytes=$(wc -c < "$OUT/$name.out") err_bytes=$(wc -c < "$OUT/$name.err")"
  echo "finished=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$OUT/$name.status"
cat "$OUT/$name.status"
[ "$state" = ANSWERED ]
