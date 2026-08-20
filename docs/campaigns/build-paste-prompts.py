#!/usr/bin/env python3
"""Assembles paste-ready prompt blocks from generation-prompts.md.

One source of truth: edit the markdown, re-run this. Each output file is a single block you can
paste into a generator with nothing left to assemble — scene + BASE DNA + negative + tool flags.
"""
import os, re
HERE = os.path.dirname(os.path.abspath(__file__))
SRC  = os.path.join(HERE, "generation-prompts.md")
OUT  = os.path.join(HERE, "prompts-paste")
md = open(SRC).read()

def fenced_after(heading_re):
    m = re.search(heading_re, md)
    if not m: raise SystemExit("missing block: " + heading_re)
    b = re.search(r"```\n(.*?)\n```", md[m.end():], re.S)
    return b.group(1).strip()

DNA = fenced_after(r"### 2\.3 The DNA block")
NEG = fenced_after(r"### 2\.4 Global negative")
ACC = fenced_after(r"### 2\.1 The accent law")

# every "### Pn — title" section, with its fenced prompt bodies
sections = re.split(r"\n### (?=P\d)", md.split("## 3. IMAGE PROMPTS")[1].split("## 4. VIDEO")[0])
os.makedirs(OUT, exist_ok=True)
written = []
for sec in sections:
    m = re.match(r"(P\d+(?:\s*/\s*P\d+)?)\s+—\s+([^\n*]+)", sec)
    if not m: continue
    pid, title = m.group(1).replace(" ", "").replace("/", "-"), m.group(2).strip()
    bodies = re.findall(r"```\n(.*?)\n```", sec, re.S)
    if not bodies: continue
    role = re.search(r"\*\*ROLE\*\*\s*(.+?)\.\s*\*\*IDEA\*\*\s*(.+?)\n```", sec, re.S)
    gate = re.search(r"\*\*GATE\*\*\s*(.+?)(?:\n|$)", sec)
    for i, body in enumerate(bodies):
        name = f"{pid}.txt" if len(bodies) == 1 else f"{pid}-{i+1}.txt"
        txt  = [f"# {pid} — {title}"]
        if role:
            r1 = " ".join(role.group(1).split()); r2 = " ".join(role.group(2).split())
            txt.append(f"# ROLE: {r1} | IDEA: {r2}")
        if gate: txt.append(f"# GATE: {re.sub(r'[*`]', '', gate.group(1)).strip()}")
        txt += ["", body.strip(), "", DNA, "", ACC, "", NEG, "",
                "--ar 4:5 --style raw --stylize 150 --sref SREF-01 --cref <LOCKED_DOG_REF>",
                "# SREF-01 = dumb/ChatGPT Image Aug 4, 2026, 01_08_30 PM (1).png  (generation-prompts.md \u00a72.6)",
                "",
                "# Type is set in post in real Black Han Sans — never generated except via GPT-4o,",
                "# and never for numbers. The violet route trace is vector, plotted from a real GPX",
                "# (docs/campaigns/generation-prompts.md §2.2). No GPX for this frame = no trace, no readout."]
        open(os.path.join(OUT, name), "w").write("\n".join(txt) + "\n")
        written.append(name)

# video: motion prompts are applied to an approved plate, so they ship with the production law
vid = md.split("### 4.4 Six standalone clips")[1].split("### 4.5")[0]
for m in re.finditer(r"\*\*(V\d) · ([^*]+)\*\*(.*?)(?=\n\*\*V\d|\Z)", vid, re.S):
    vid_id, title, body = m.group(1), m.group(2).strip(), m.group(3).strip()
    prompt = re.search(r"`([^`]{60,})`", body)
    txt = [f"# {vid_id} — {title}", "# IMAGE-TO-VIDEO ONLY. Animate an approved still; never text-to-video.",
           "# Reject at 0.25x on: paw-count change, gait morph, detached/floating leash,",
           "# duplicate tail, eye glow, human drift on a long hold. Keep every shot <= 3s.", ""]
    txt.append(prompt.group(1).strip() if prompt else body)
    txt += ["", "NEGATIVE (motion): no morphing limbs, no changing paw count, no gait transitions,",
            "no floating or detaching leash, no duplicated tail, no eye glow, no camera shake,",
            "no zoom, no text, no logos, no GPS or map overlays, no numbers.", "",
            "# Sound is designed in post: human exhale + dog panting, breath before music.",
            "# Music by BPM and energy only, royalty-free licensed if the clip will ever be boosted."]
    open(os.path.join(OUT, f"{vid_id}.txt"), "w").write("\n".join(txt) + "\n")
    written.append(f"{vid_id}.txt")

# R1 master film: one file per cut, so the 14-cut table is usable at the keyboard
r1 = md.split("### 4.3 R1")[1].split("### 4.4")[0]
for row in re.findall(r"^\| (\d+) \| ([\d.]+) \| ([^|]+) \| `([^`]+)` \|", r1, re.M):
    n, secs, plate, motion = row
    txt = [f"# R1 cut {int(n):02d} — {secs}s — source plate: {plate.strip()}",
           "# IMAGE-TO-VIDEO ONLY. Animate the approved plate; never text-to-video.",
           "# Reject at 0.25x: paw-count change, gait morph, floating leash, duplicate tail, eye glow.",
           "", motion.strip(), "",
           "NEGATIVE (motion): no morphing limbs, no changing paw count, no gait transitions,",
           "no floating or detaching leash, no duplicated tail, no eye glow, no unrequested camera",
           "move, no text, no logos, no GPS or map overlays, no numbers.", "",
           "# On-screen Korean and sound for this cut: docs/instagram/reel-scripts.md \u00a71."]
    open(os.path.join(OUT, f"R1-{int(n):02d}.txt"), "w").write("\n".join(txt) + "\n")
    written.append(f"R1-{int(n):02d}.txt")

print(f"{len(written)} paste-ready blocks -> {OUT}")
for w in sorted(written): print("  ", w)
