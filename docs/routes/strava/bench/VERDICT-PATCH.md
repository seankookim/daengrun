# Review layer — what to mirror into the published artifact

The accept / reject / comment layer landed in `bench/index.html` (the local copy). The artifact is
assembled from `head.html` + `body.html` + `script.html`, so the same change is five inserts. Every
snippet below is verbatim from the working local page — copy, do not retype.

Nothing here touches the route list build, selection, the map, the SVG shape, the elevation
profile, the GPX drop-replace, or any measurement. The only edits inside existing code are three
one-line hooks (§3, §5a, §5b).

---

## 1. `head.html` — append to the end of the `<style>` block

Uses only existing tokens (`--sage`, `--coral-deep`, `--accent`, `--line`, `--surface`,
`--surface-2`, `--ink`, `--ink-3`). The two `color-mix()` rules each repeat the property with a
plain-token fallback first, so a browser without `color-mix` still gets a valid background and the
state stays legible via the inset ring.

```css
/* ---- review layer: verdict, comment, per-row marks, export ---------------- */
.sr{position:absolute;width:1px;height:1px;margin:-1px;padding:0;overflow:hidden;
  clip:rect(0 0 0 0);white-space:nowrap;border:0}
.hright{display:flex;flex-direction:column;align-items:flex-end;gap:9px}
.tally{flex-wrap:wrap;justify-content:flex-end}
.tally b.acc{color:var(--sage)}
.tally b.rej{color:var(--coral-deep)}
.irow{display:flex;align-items:flex-start;gap:8px;justify-content:space-between}
.vmark{flex:none;width:16px;height:16px;margin-top:1px;border-radius:50%;
  border:1px solid var(--line);display:inline-flex;align-items:center;justify-content:center;
  font-size:10px;font-weight:700;line-height:1;color:var(--ink-3)}
.vmark[data-v="none"]{opacity:.5}
.vmark[data-v="accept"]{border-color:var(--sage);color:var(--sage);background:var(--surface-2)}
.vmark[data-v="reject"]{border-color:var(--coral-deep);color:var(--coral-deep);background:var(--surface-2)}
.vmark[data-v="note"]{border-color:var(--accent);color:var(--accent);background:var(--surface-2)}
.review{border:1px solid var(--line);border-radius:10px;background:var(--surface-2);
  padding:13px 14px;margin-bottom:18px}
.rvhead{display:flex;justify-content:space-between;align-items:baseline;gap:10px;
  flex-wrap:wrap;margin-bottom:10px}
.rvstate{font-size:10px;letter-spacing:.11em;text-transform:uppercase;color:var(--ink-3);font-weight:660}
.rvstate.acc{color:var(--sage)}
.rvstate.rej{color:var(--coral-deep)}
.rvhint{font-size:11.5px;color:var(--ink-3)}
.vbtns{display:flex;gap:8px;flex-wrap:wrap;align-items:center}
.vbtn{appearance:none;border:1px solid var(--line);background:var(--surface);color:var(--ink);
  font:inherit;font-size:13px;font-weight:620;padding:8px 16px;border-radius:8px;cursor:pointer;
  display:inline-flex;align-items:center;gap:7px}
.vbtn .g{font-size:11.5px;line-height:1;color:var(--ink-3)}
.vbtn:focus-visible{outline:2px solid var(--accent);outline-offset:2px}
.vbtn.acc:hover{border-color:var(--sage)}
.vbtn.acc:hover .g{color:var(--sage)}
.vbtn.rej:hover{border-color:var(--coral-deep)}
.vbtn.rej:hover .g{color:var(--coral-deep)}
.vbtn.acc[aria-pressed="true"]{border-color:var(--sage);box-shadow:inset 0 0 0 1px var(--sage);
  background:var(--surface);background:color-mix(in srgb,var(--sage) 15%,var(--surface))}
.vbtn.acc[aria-pressed="true"] .g{color:var(--sage)}
.vbtn.rej[aria-pressed="true"]{border-color:var(--coral-deep);box-shadow:inset 0 0 0 1px var(--coral-deep);
  background:var(--surface);background:color-mix(in srgb,var(--coral-deep) 15%,var(--surface))}
.vbtn.rej[aria-pressed="true"] .g{color:var(--coral-deep)}
.clabel{display:block;font-size:10px;letter-spacing:.11em;text-transform:uppercase;
  color:var(--ink-3);font-weight:660;margin:14px 0 6px}
.ctext{width:100%;min-height:74px;font:inherit;font-size:13.5px;border:1px solid var(--line);
  border-radius:8px;padding:9px 10px;background:var(--surface);color:var(--ink);resize:vertical}
.ctext::placeholder{color:var(--ink-3)}
.ctext:focus-visible{outline:2px solid var(--accent);outline-offset:1px}
.saveline{margin-top:8px;font-size:12px;color:var(--sage);font-weight:580;min-height:17px}
.saveline.bad{color:var(--coral-deep)}
.exportbox{margin-top:20px;padding:16px 18px}
.exportbox textarea{width:100%;min-height:220px;font:11.5px/1.5 ui-monospace,SFMono-Regular,Menlo,monospace;
  border:1px solid var(--line);border-radius:8px;padding:10px;background:var(--surface-2);
  color:var(--ink);resize:vertical}
.exportbox textarea:focus-visible{outline:2px solid var(--accent);outline-offset:1px}
```

No transition or animation is introduced, so the existing `prefers-reduced-motion` rule stays
sufficient.

---

## 2. `body.html` — three markup changes

### 2a. Header: wrap the tally, add three counters and the export button

Replace the whole `<div class="tally">…</div>` in `<header>` with:

```html
<div class="hright">
  <div class="tally">
    <div><b id="tCount">0</b>routes</div>
    <div><b id="tTowns">0</b>towns</div>
    <div><b id="tKm">0</b>km drawn</div>
    <div><b class="acc" id="tAcc">0</b>accepted</div>
    <div><b class="rej" id="tRej">0</b>rejected</div>
    <div><b id="tLeft">0</b>unreviewed</div>
  </div>
  <button class="btn" id="exportBtn" type="button">Export review</button>
</div>
```

### 2b. Detail panel: the verdict block, immediately BEFORE `<div class="stats" id="dStats">`

Above the stats on purpose — it is the first thing under the route name.

```html
<div class="review" id="review">
  <div class="rvhead">
    <span class="rvstate" id="rvState">Not reviewed</span>
    <span class="rvhint">A accept · R reject · C clear</span>
  </div>
  <div class="vbtns" role="group" aria-label="Verdict for this route">
    <button class="vbtn acc" id="bAccept" type="button" aria-pressed="false"><span class="g" aria-hidden="true">✓</span>Accept</button>
    <button class="vbtn rej" id="bReject" type="button" aria-pressed="false"><span class="g" aria-hidden="true">✕</span>Reject</button>
    <button class="btn" id="bClear" type="button">Clear</button>
  </div>
  <label class="clabel" for="comment">What's wrong with it / what to change</label>
  <textarea class="ctext" id="comment" placeholder="e.g. the north leg cuts through the parking lot — take it along the river path instead"></textarea>
  <div class="saveline" id="saveLine"></div>
</div>
```

### 2c. Export panel: after `</section>` (the detail panel) and after the `</div>` that closes `.grid`, still inside `.wrap`

```html
<section class="panel exportbox" id="exportBox" hidden aria-label="Review export">
  <div class="vlabel"><span>Review export</span><span id="exCount"></span></div>
  <textarea id="exText" readonly aria-label="Review export JSON"></textarea>
  <div class="btnrow">
    <button class="btn" id="exCopy" type="button">Copy JSON</button>
    <button class="btn" id="exClose" type="button">Close</button>
    <span class="ok" id="exOk" hidden>Copied</span>
  </div>
</section>
```

---

## 3. `body.html` (or wherever `buildList()` lives) — the list row gains a mark

Inside `buildList()`, the row template's `<div class="iname">…</div>` becomes a two-child row:

```js
h+=`<button class="item" data-name="${r.name.replace(/"/g,'&quot;')}" aria-current="false">
  <div class="irow">
    <div class="iname">${r.name}</div>
    <span class="vmark" data-v="none"><span class="vg" aria-hidden="true"></span><span class="sr"></span></span>
  </div>
  <div class="imeta">…unchanged…</div>
</button>`;
```

and one line after `$('list').innerHTML=h;`:

```js
  paintMarks();
```

---

## 4. `script.html` — the review block

Paste as one contiguous block anywhere at top level of the script (in the local page it sits
between the GPX section and the Naver section). The trailing `loadReview();` runs at parse time,
which is what makes stored verdicts available before the first `render()`.

```js
// ---- Review layer ----------------------------------------------------------
// Accept / reject / comment per route, keyed by route name (names are unique in
// the catalog; routeId is null for most rows so it cannot be the key). Stored in
// localStorage only — nothing leaves the browser, and the export button is the
// only way the verdicts travel anywhere.
const RKEY='routeBench.review.v1';
let REVIEW={}, storeOK=true;

function loadReview(){
  try{ const raw=localStorage.getItem(RKEY); REVIEW=raw?(JSON.parse(raw)||{}):{}; }
  catch(e){ REVIEW={}; storeOK=false; }
  if(typeof REVIEW!=='object'||REVIEW===null||Array.isArray(REVIEW)) REVIEW={};
}
function saveReview(){
  try{ localStorage.setItem(RKEY,JSON.stringify(REVIEW)); storeOK=true; }
  catch(e){ storeOK=false; }
  return storeOK;
}
const entryOf=n=>REVIEW[n]||null;
const judged=e=>!!(e&&(e.verdict||(e.comment||'').trim()));

function writeEntry(name,verdict,comment){
  const c=(comment||'').trim();
  if(!verdict&&!c) delete REVIEW[name];
  else REVIEW[name]={verdict:verdict||null,comment:c,ts:Date.now()};
  saveReview(); paintMarks(); paintTally(); paintSaveLine(name);
}
function setVerdict(name,v){
  const e=entryOf(name);
  writeEntry(name,v,e?e.comment:'');
  paintButtons(name);
}

const MARK={accept:{g:'✓',t:'accepted'},reject:{g:'✕',t:'rejected'},
  note:{g:'•',t:'commented, no verdict'},none:{g:'',t:'not reviewed'}};
function stateOf(name){
  const e=entryOf(name); if(!e) return 'none';
  if(e.verdict==='accept'||e.verdict==='reject') return e.verdict;
  return (e.comment||'').trim()?'note':'none';
}
function paintMarks(){
  document.querySelectorAll('.item').forEach(b=>{
    const st=stateOf(b.dataset.name), mk=MARK[st], el=b.querySelector('.vmark');
    if(!el) return;
    el.dataset.v=st;
    el.querySelector('.vg').textContent=mk.g;
    el.querySelector('.sr').textContent=mk.t;
    el.title=mk.t;
  });
}
function paintTally(){
  let a=0,r=0;
  ROUTES.forEach(x=>{ const s=stateOf(x.name); if(s==='accept')a++; else if(s==='reject')r++; });
  $('tAcc').textContent=a; $('tRej').textContent=r;
  $('tLeft').textContent=Math.max(ROUTES.length-a-r,0);
}
function paintButtons(name){
  const e=entryOf(name), v=e?e.verdict:null;
  $('bAccept').setAttribute('aria-pressed', v==='accept'?'true':'false');
  $('bReject').setAttribute('aria-pressed', v==='reject'?'true':'false');
  const st=$('rvState');
  st.classList.toggle('acc',v==='accept'); st.classList.toggle('rej',v==='reject');
  st.textContent = v==='accept'?'Accepted' : v==='reject'?'Rejected'
    : (e&&(e.comment||'').trim())?'Comment only — no verdict yet' : 'Not reviewed';
}
function paintSaveLine(name){
  const el=$('saveLine'), e=entryOf(name);
  el.classList.toggle('bad',!storeOK);
  if(!storeOK){ el.textContent='Could not save — this browser is blocking localStorage.'; return; }
  if(!e){ el.textContent=''; return; }
  const d=new Date(e.ts||Date.now());
  const hh=String(d.getHours()).padStart(2,'0'), mm=String(d.getMinutes()).padStart(2,'0');
  el.textContent='Saved in this browser · '+hh+':'+mm;
}
function paintReview(name){
  $('comment').value=(entryOf(name)||{}).comment||'';
  paintButtons(name); paintSaveLine(name);
}

$('bAccept').addEventListener('click',()=>{ if(cur) setVerdict(cur.name,'accept'); });
$('bReject').addEventListener('click',()=>{ if(cur) setVerdict(cur.name,'reject'); });
$('bClear').addEventListener('click',()=>{ if(!cur) return;
  delete REVIEW[cur.name]; saveReview();
  $('comment').value=''; paintMarks(); paintTally(); paintButtons(cur.name); paintSaveLine(cur.name); });
$('comment').addEventListener('input',()=>{ if(!cur) return;
  const e=entryOf(cur.name);
  writeEntry(cur.name, e?e.verdict:null, $('comment').value);
  paintButtons(cur.name); });

// Letter shortcuts, ignored while typing so the comment box keeps its letters.
document.addEventListener('keydown',e=>{
  if(e.metaKey||e.ctrlKey||e.altKey||!cur) return;
  const t=e.target, tag=t&&t.tagName;
  if(tag==='INPUT'||tag==='TEXTAREA'||(t&&t.isContentEditable)) return;
  const k=e.key.toLowerCase();
  if(k==='a'){ e.preventDefault(); setVerdict(cur.name,'accept'); }
  else if(k==='r'){ e.preventDefault(); setVerdict(cur.name,'reject'); }
  else if(k==='c'){ e.preventDefault(); $('bClear').click(); }
});

// ---- Export ----------------------------------------------------------------
function exportRows(){
  const rows=[], seen=new Set();
  ROUTES.forEach(r=>{ const e=entryOf(r.name); if(!judged(e)) return; seen.add(r.name);
    rows.push({name:r.name, routeId:r.routeId==null?null:r.routeId,
      verdict:e.verdict||null, comment:e.comment||''}); });
  // Verdicts left over from a route that has since been renamed still belong to
  // him — carried through rather than silently dropped.
  Object.keys(REVIEW).forEach(n=>{ if(seen.has(n)) return; const e=REVIEW[n]; if(!judged(e)) return;
    rows.push({name:n, routeId:null, verdict:e.verdict||null, comment:e.comment||''}); });
  return rows;
}
function openExport(){
  const rows=exportRows(), box=$('exportBox');
  $('exText').value=JSON.stringify(rows,null,2);
  $('exCount').textContent=rows.length+(rows.length===1?' route judged':' routes judged');
  box.hidden=false; $('exText').focus(); $('exText').select();
}
$('exportBtn').addEventListener('click',openExport);
$('exClose').addEventListener('click',()=>{ $('exportBox').hidden=true; $('exportBtn').focus(); });
$('exCopy').addEventListener('click',async()=>{
  try{ await navigator.clipboard.writeText($('exText').value); }
  catch(e){ $('exText').select(); document.execCommand&&document.execCommand('copy'); }
  $('exOk').hidden=false; setTimeout(()=>$('exOk').hidden=true,1600);
});

loadReview();
```

Assumes, as in the local page: `$ = id => document.getElementById(id)`, the module-level `cur`
holding the selected route, and `ROUTES` being an array of `{name, routeId, …}`.

---

## 5. `script.html` — two one-line hooks in existing functions

**5a.** Last line inside `render(r)`, after `$('dropSub').textContent=…`:

```js
  paintReview(r.name);
```

**5b.** In the boot sequence, alongside `buildList(); render(ROUTES[0]);` — in the local page the
line became:

```js
  buildList(); render(ROUTES[0]); paintTally(); bootNaver();
```

In the artifact there is no `fetch`/`bootNaver`; put `paintTally()` immediately after the first
`render(...)` call, whatever that boot line looks like there.

---

## Behaviour contract (what I verified locally, headless Chromium)

- Verdict states: accept / reject / unset. `Clear` unsets; clicking a verdict is idempotent.
- A route counts as *judged* if it has a verdict **or** a non-empty comment. Comment-only routes
  show an accent `•` in the list and read "Comment only — no verdict yet"; they are exported with
  `"verdict": null`.
- Storage key `routeBench.review.v1`, shape `{ "<route name>": {verdict, comment, ts} }`. A route
  with neither verdict nor comment is deleted from the object, not stored empty.
- Corrupt or unreadable storage degrades to an empty review; the page still renders. A write that
  throws (private mode) turns the save line coral and says so instead of lying "Saved".
- Export is `JSON.stringify(rows, null, 2)` of `{name, routeId, verdict, comment}`, judged routes
  only, catalog order. Empty review exports `[]`.
- Header counters: accepted / rejected / unreviewed, where unreviewed = total − accepted −
  rejected (a comment-only route still counts as unreviewed, because it has no verdict).
