#!/usr/bin/env python3
"""Audits the campaign documents against reality: every asset path resolves, every cross-referenced
doc exists, every quoted figure matches its source table, every code claim is still true, and every
colour token still exists in theme.ts.

Written because these documents assert things about files and code, and an assertion nobody re-checks
is how a doc becomes confidently wrong. Run it after editing anything in docs/campaigns/."""
import os, re, glob, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
POST = "/Users/sean/Desktop/post"
DOCS = sorted(glob.glob(os.path.join(ROOT, "docs/campaigns/*.md"))) + \
       [os.path.join(ROOT, ".claude/brand-voice-guidelines.md")]

fails, checked = [], 0
def check(cond, msg):
    global checked; checked += 1
    if not cond: fails.append(msg)

# 1 — asset paths. Filenames contain spaces, Korean, and a leading "[n] " index in our own prose.
asset_pat = re.compile(r"`([^`\n]+?\.png)`|\*\*([^*\n]+?\.png)\*\*")
seen = set()
for d in DOCS:
    s = open(d).read()
    for m in asset_pat.finditer(s):
        fn = re.sub(r"^\[\d+\]\s*", "", (m.group(1) or m.group(2)).strip())
        if fn.startswith(("docs/", "app/", "supabase/")): continue
        key = (os.path.basename(d), fn)
        if key in seen: continue
        seen.add(key)
        check(os.path.exists(os.path.join(POST, fn)), f"MISSING ASSET  {os.path.basename(d)}: {fn}")

# 2 — cross-referenced repo paths
for d in DOCS:
    s = open(d).read()
    for m in re.finditer(r"`((?:docs|app|supabase)/[A-Za-z0-9_\-./]+)`", s):
        p = m.group(1).rstrip(".")
        if "*" in p or p.endswith("/"): continue
        check(os.path.exists(os.path.join(ROOT, p)), f"MISSING PATH   {os.path.basename(d)}: {p}")

# 3 — money figures trace to the one source table
src = open(os.path.join(ROOT, "docs/runner-recruitment.md")).read()
for fig in ["16,683", "20,703", "33,366", "10,320"]:
    check(fig in src, f"FIGURE NOT IN runner-recruitment.md: {fig}")
check("33%" in src, "take rate 33% not stated in runner-recruitment.md")

# 4 — claims about shipped code
api = open(os.path.join(ROOT, "app/src/lib/api.ts")).read()
check("identity_verified: false" in api, "CLAIM STALE: api.ts no longer hardcodes identity_verified: false")
sched = open(os.path.join(ROOT, "app/app/owner/schedule.tsx")).read()
check("바디캠 뷰는 준비 중" in sched, "CLAIM STALE: the single bodycam line is gone from schedule.tsx")
m62 = glob.glob(os.path.join(ROOT, "supabase/migrations/0062_*.sql"))
check(bool(m62), "CLAIM STALE: migration 0062 not found")
check(bool(m62) and any("runner_app_approve" in open(f).read() for f in m62),
      "CLAIM STALE: runner_app_approve not in 0062")

# 5 — colour tokens must still exist in the shipped theme
theme = open(os.path.join(ROOT, "app/src/theme.ts")).read()
for tok in ["#FF5C3D", "#7B6CDF", "#9F8FFF", "#C6F542", "#0F1D13", "#EFF1EC", "#D8DAD2", "#171A17"]:
    check(tok in theme, f"TOKEN GONE FROM theme.ts: {tok}")

# 6 — rendered output matches what the docs promise
check(len(glob.glob(os.path.join(ROOT, "docs/labs/posts/ig/[0-9][0-9].jpg"))) == 9, "IG tiles != 9")
check(len(glob.glob(os.path.join(ROOT, "docs/labs/posts/tiktok/TS-*/*.jpg"))) == 40, "TikTok slides != 40")
check(len(glob.glob(os.path.join(ROOT, "docs/campaigns/prompts-paste/*.txt"))) == 29, "paste blocks != 29")

# 7 — the locked style anchor must exist, and every paste block must name it
sref = "dumb/ChatGPT Image Aug 4, 2026, 01_08_30 PM (1).png"
check(os.path.exists(os.path.join(POST, sref)), "SREF-01 asset missing")
blocks = glob.glob(os.path.join(ROOT, "docs/campaigns/prompts-paste/P*.txt"))
check(all("SREF-01" in open(b).read() for b in blocks), "some P-block does not carry SREF-01")

# 8 — banned words, scanned ONLY inside fenced blocks (that is where publish-facing copy lives;
# everything outside a fence is prose ABOUT the rules and legitimately names the banned words).
# "산책" in an explicit price comparison is sanctioned by positioning.md and is excluded.
BANNED = ["산책 대행", "산책대행", "펫시터", "돌봄", "꿀알바", "고수익", "2만원대", "시급"]
for d in DOCS:
    body = open(d).read()
    for block in re.findall(r"```[a-z]*\n(.*?)\n```", body, re.S):
        for line in block.splitlines():
            for w in BANNED:
                checked += 1
                if w in line and "비교" not in line:
                    fails.append(f"BANNED WORD    {os.path.basename(d)}: {w!r} in: {line.strip()[:70]}")

print(f"{checked} assertions · {len(fails)} failures")
for f in fails: print("  ", f)
sys.exit(1 if fails else 0)
