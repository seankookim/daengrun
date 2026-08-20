#!/usr/bin/env python3
import base64, io, re, subprocess, sys, os
from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = "/Users/sean/dev/daengrun"
SRC  = f"{ROOT}/docs/labs/home-premium-lab.html"
OUT  = f"{ROOT}/docs/labs/home-premium-lab.html"

BELL = ('<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" '
        'stroke-linecap="round"><path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"/>'
        '<path d="M13.7 21a2 2 0 0 1-3.4 0"/></svg>')
CHEV = ('<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" '
        'stroke-linecap="round" stroke-linejoin="round"><path d="M9 18l6-6-6-6"/></svg>')
ARROW = ('<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" '
         'stroke-linecap="round" stroke-linejoin="round"><path d="M9 18l6-6-6-6"/></svg>')

def bar():
    return ('<div class="bar"><span>11:03</span><span class="isl"></span>'
            '<span class="rt">▮▮▮</span></div>')

def mast(logo_h, wm_px):
    return (f'<div class="mast"><div class="sp"></div><div class="lg">'
            f'<img src="data:image/png;base64,__LOGO__" style="height:{logo_h}px">'
            f'<span class="wm" style="font-size:{wm_px}px">도그스하이</span></div>'
            f'<div class="bell">{BELL}<i></i></div></div>')

def state(chip='확정됨', arrow=True):
    a = f'<span style="opacity:.4;display:flex;width:15px">{ARROW}</span>' if arrow else ''
    return (f'<div class="st"><span class="when"><span class="num">8월 4일</span> (화) '
            f'<span class="num">오후 3:30</span></span>'
            f'<span class="who">s4kim2025</span>'
            f'<span class="chip">{chip}</span>{a}</div>')

def cta(size=31):
    return (f'<div class="cta"><b style="font-size:{size}px">미리 예약</b>{CHEV}</div>')

def kick(t='동네'):
    return f'<div class="kickrow">{t}</div>'

# ── club interiors, one per variant ───────────────────────────────────────
CLUBS = {}

CLUBS[1] = kick() + '''<div class="club"><div class="grain"></div>
<div style="display:flex;align-items:center;gap:12px;position:relative">
  <div class="mg foil">반</div>
  <div style="flex:1;min-width:0">
    <div class="cl-name">반포동 하이클럽</div>
    <div class="cl-meta">호스트 · 멤버 1명</div>
  </div>
  <div style="color:var(--l-goldSheen);width:16px;display:flex">''' + ARROW + '''</div>
</div></div>'''

CLUBS[2] = kick() + '''<div class="club">
<div class="edge foiledge"></div>
<div class="tk-top">
  <div class="mono-sm" style="color:var(--l-goldSheen);margin-bottom:7px">MEMBER · 반포</div>
  <div class="cl-name">반포동 하이클럽</div>
  <div class="cl-meta">호스트 · 멤버 1명</div>
</div>
<div class="tk-perf"></div>
<div class="tk-bot">
  <span class="mono-sm" style="color:var(--n-dim)">NO. 0001</span>
  <span style="color:var(--l-goldSheen);width:15px;display:flex">''' + ARROW + '''</span>
</div></div>'''

CLUBS[3] = '''<div class="club"><div class="grain"></div>
<div style="position:relative">
  <div class="mono-sm" style="color:var(--l-goldSheen)">동네 · 클럽</div>
  <div class="rule"></div>
  <div class="cl-name">반포동<br>하이클럽</div>
  <div class="cl-meta">호스트 · 멤버 1명</div>
  <div style="margin-top:18px;display:inline-flex;align-items:center;gap:7px;color:#fff;
    border-bottom:1px solid var(--l-goldSheen);padding-bottom:4px;font-size:14px;font-weight:700">
    세션 열기 <span style="width:13px;display:flex;color:var(--l-goldSheen)">''' + ARROW + '''</span></div>
</div></div>'''

CLUBS[4] = kick() + '''<div class="club"><div class="grain"></div>
<div style="position:relative">
  <div class="crest foil">반</div>
  <div class="cl-name">반포동 하이클럽</div>
  <div class="cl-meta">호스트 · 멤버 1명</div>
  <div class="lau"><span></span>
    <span class="mono-sm" style="color:var(--l-goldSheen)">EST. 2026</span><span></span></div>
</div></div>'''

CLUBS[5] = '''<div class="club">
  <div class="dateline">동네 · 클럽</div>
  <div class="cl-name">반포동 하이클럽</div>
  <div class="cl-meta">호스트 · 멤버 1명 — 탭해서 세션을 엽니다</div>
</div>'''

CLUBS[6] = '''<div class="gold-bar foiledge"></div><div class="club"><div class="grain"></div>
<div style="position:relative;display:flex;align-items:center;gap:13px">
  <div style="flex:1">
    <div class="mono-sm" style="color:var(--l-goldSheen);margin-bottom:6px">동네 클럽</div>
    <div class="cl-name">반포동 하이클럽</div>
    <div class="cl-meta">호스트 · 멤버 1명</div>
  </div>
  <div style="color:var(--l-goldSheen);width:17px;display:flex">''' + ARROW + '''</div>
</div></div>'''

CLUBS[7] = kick() + '''<div class="club">
  <div class="emb">반포동 하이클럽</div>
  <div class="cl-meta" style="margin-top:7px">호스트 · 멤버 1명</div>
  <div style="margin-top:13px;height:1px;background:#E0CFA4"></div>
  <div class="mono-sm" style="color:#8A7434;margin-top:11px">MEMBER SINCE 2026</div>
</div>'''

CLUBS[8] = kick() + '''<div class="club">
<div style="display:flex;align-items:center;gap:12px">
  <div class="mg foil" style="border-color:var(--l-goldSheen)">반</div>
  <div style="flex:1;min-width:0">
    <div class="cl-name">반포동 하이클럽</div>
    <div class="cl-meta">호스트 · 멤버 1명</div>
  </div>
  <div style="color:var(--l-goldSheen);width:16px;display:flex">''' + ARROW + '''</div>
</div></div>'''

CLUBS[9] = kick() + '''<div class="club"><div class="grain"></div>
<div style="position:relative">
  <div style="display:flex;align-items:flex-start;justify-content:space-between;gap:12px">
    <div style="min-width:0">
      <div class="mono-sm" style="color:var(--l-goldSheen);margin-bottom:6px">동네 클럽 · 1</div>
      <div class="cl-name">반포동 하이클럽</div>
      <div class="cl-meta">호스트 · 멤버 1명</div>
    </div>
    <div style="width:26px;height:26px;flex:0 0 26px;border-radius:0 6px 0 6px;
      background:linear-gradient(135deg,var(--l-goldSheen),#8A7434)"></div>
  </div>
  <div style="margin-top:14px;padding-top:12px;border-top:1px solid var(--n-edge);display:flex;
    align-items:center;justify-content:space-between">
    <span style="color:#fff;font-size:14px;font-weight:700">세션 열기</span>
    <span style="color:var(--l-goldSheen);width:15px;display:flex">''' + ARROW + '''</span>
  </div>
</div></div>
<div class="stackpeek"></div>
<div class="stackpeek" style="margin:0 34px;opacity:.6"></div>'''

CLUBS[10] = kick() + '''<div class="club"><div class="grain"></div>
<div style="position:absolute;left:-3px;top:-1px;bottom:-1px;width:3px" class="foiledge"></div>
<div style="display:flex;align-items:center;gap:12px;position:relative">
  <div style="flex:1;min-width:0">
    <div class="cl-name">반포동 하이클럽</div>
    <div class="cl-meta">호스트 · 멤버 1명</div>
  </div>
  <div style="color:var(--l-goldSheen);width:16px;display:flex">''' + ARROW + '''</div>
</div></div>'''

# num, css, name, en, thesis, route, logoH, wm, cta, notes
V = [
 (1,'v1','정렬','ALIGNED','교리를 그대로 실행한 기준선. 로고 44 · 초록 칩 · 코랄 면 · 클럽은 나이트 플레이트에 포일 모노그램.','B',44,30,31,
  ['<b>클럽</b> 어두운 판 + 금색 모노그램 — 흰 바탕의 글자에서 <em>물건</em>으로','<b>위험</b> 가장 안전하고 가장 안 놀랍다']),
 (2,'v2','티켓','TICKET','상태 줄과 클럽을 둘 다 티켓으로. 앱의 세리머니 세계(여권·씰)를 홈으로 끌어온다.','B',44,30,31,
  ['<b>클럽</b> 퍼포레이션 + 포일 상단 엣지 + 일련번호','<b>주의</b> 티켓이 둘이라 L1 경계 — 상태 티켓을 더 조용히']),
 (3,'v3','모노리스','MONOLITH','클럽을 풀블리드 어두운 덩어리로 승격. 티어 3이 화면의 무게 중심이 된다.','B',48,32,31,
  ['<b>클럽</b> 좌우 여백 없음 · 디스플레이 서체 이름 · 금색 규칙선','<b>대가</b> 클럽이 CTA와 무게를 겨룬다 — 커뮤니티가 목표일 때만']),
 (4,'v4','크레스트','CREST','회원제의 시각 언어. 원형 크레스트 + 포일 모노그램 + 설립 연도.','B',44,30,31,
  ['<b>클럽</b> 가운데 정렬 크레스트 — 배지·훈장의 문법','<b>강점</b> “멤버”라는 말을 쓰지 않고 멤버십을 말한다']),
 (5,'v5','신문','EDITORIAL','서체 예산을 다시 쓴다. 워드마크가 한 단계 내려가고 클럽이 디스플레이 서체를 얻는다.','A',40,26,31,
  ['<b>클럽</b> 흰 바탕 유지 · 굵은 룰 + 30px 디스플레이 이름','<b>필요</b> 당신의 재정 — L3 예산이 워드마크에서 클럽으로 이동']),
 (6,'v6','슬래브','SLAB','색면 스택. CTA 코랄 슬래브와 클럽 나이트 슬래브가 화면 폭을 꽉 채워 붙는다.','B',46,31,37,
  ['<b>CTA</b> 37px · 풀블리드 — 화면 최대 활자','<b>클럽</b> 금색 4px 바가 두 슬래브를 가른다']),
 (7,'v7','헤어라인','HAIRLINE','극단적 절제. 유일한 채도는 CTA 외곽선. 클럽은 크림 위 엠보스로 프리미엄을 만든다.','B',42,29,31,
  ['<b>CTA</b> 코랄 아웃라인 — 면을 쓰지 않는 유일한 안','<b>클럽</b> 금박 대신 <em>양각</em> — 종이의 프리미엄']),
 (8,'v8','나이트','NIGHT','화면 전체가 나이트 월드. 프리미엄이 블록이 아니라 화면 자체가 된다.','B',46,31,31,
  ['<b>전체</b> 캔버스가 #0D0A1E — 클럽이 “특별한 블록”일 필요가 없어진다','<b>대가</b> 홈의 밝은 성격을 포기 · 다른 탭과 이질']),
 (9,'v9','덱','DECK','깊이로 위계를 만든다. 카드가 층으로 쌓이고 클럽 카드가 가장 높이 들린다.','B',44,30,31,
  ['<b>클럽</b> 가장 큰 그림자 + 뒤에 겹친 카드 한 장이 비친다','<b>강점</b> 색을 더 쓰지 않고 클럽을 올린다']),
 (10,'v10','레일','RAIL','좌측 3px 레일이 티어를 인코딩한다. 초록=상태 · 코랄=행동 · 금색=클럽.','B',44,30,31,
  ['<b>전체</b> 레일 색만 읽어도 위계가 보인다','<b>강점</b> L2를 가장 문자 그대로 실행 — 색이 곧 상태']),
]

def spec(v):
    n,css,name,en,thesis,route,lh,wm,ct,notes = v
    circ = '①②③④⑤⑥⑦⑧⑨⑩'[n-1]
    body = bar() + mast(lh,wm) + state() + cta(ct) + CLUBS[n]
    notes_html = ''.join(f'<div>{x}</div>' for x in notes)
    rcls = 'rA' if route=='A' else 'rB'
    rtxt = '예산 경로' if route=='A' else '재질 경로'
    return f'''<div class="spec">
  <div class="spec-h"><span class="spec-n">{circ}</span>
    <span class="spec-t">{name}<small>{en}</small></span>
    <span class="route {rcls}">{rtxt}</span></div>
  <div class="spec-d">{thesis}</div>
  <div class="ph {css}">{body}</div>
  <div class="spec-f">{notes_html}</div>
</div>'''

specimens = '\n'.join(spec(v) for v in V)

# ── ⑦ stitch-ink exploration on the beige plate ──────────────────────────
def lum(h):
    def f(c):
        c = int(h[i:i+2],16)/255
        return c/12.92 if c <= .03928 else ((c+.055)/1.055)**2.4
    o=[]
    for i in (1,3,5): o.append(f(i))
    return .2126*o[0]+.7152*o[1]+.0722*o[2]
def ratio(a,b):
    la,lb=lum(a),lum(b)
    hi,lo=max(la,lb),min(la,lb)
    return (hi+.05)/(lo+.05)

PLATE='#F4EBD3'
INKS=[
 ('#7A6528','골드 각인','지금 ⑦의 값. 판과 같은 계열이라 가장 “한 몸”으로 보인다.'),
 ('#6E2A22','옥스블러드','와인/가죽의 색. 브랜드 빨강과 친척이라 CTA와 싸우지 않고 격을 올린다.'),
 ('#C6472C','브랜드 딥 레드','랩이 쓰던 딥 레드 그대로. 클럽과 CTA가 같은 피를 나눈 것처럼 읽힌다.'),
 ('#2C4A33','딥 포레스트','헤리티지·클럽하우스. 초록이 확정 칩과 뜻이 겹칠 위험은 채도로 갈린다.'),
 ('#221E3D','잉크 네이비','앱의 제목 잉크(head) 그대로. 가장 안전하고 가장 시스템에 가깝다.'),
 ('#4A3DA8','클럽 바이올렛','clubInk — 클럽 세계가 이미 쓰는 보라. 홈에서도 클럽임을 색으로 말한다.'),
 ('#3A2E12','에스프레소','거의 갈색. 판이 종이처럼, 글자가 잉크처럼 — 가장 인쇄물에 가깝다.'),
 ('#1A1712','레터프레스 블랙','고전 활판. 가장 강하지만 판의 따뜻함을 반쯤 눌러 버린다.'),
]

def stile(hexv,name,note):
    r = ratio(hexv, PLATE)
    ok = r >= 4.5
    cls = 'crok' if ok else 'crlo'
    lab = f'{r:.1f}:1' + ('' if ok else ' 낮음')
    return f'''<div class="stwrap">
  <div class="stile">
    <div class="en" style="color:{hexv};text-shadow:0 1px 0 rgba(255,255,255,.95),0 -1px 0 rgba(96,78,32,.26)">반포동 하이클럽</div>
    <div class="mt" style="color:{hexv};opacity:.72">호스트 · 멤버 1명</div>
    <div class="rl"></div>
    <div class="ms" style="color:{hexv};opacity:.66">MEMBER SINCE 2026</div>
  </div>
  <div class="stcap"><b>{hexv}</b> {name}<span class="cr {cls}">{lab}</span></div>
  <div class="stnote">{note}</div>
</div>'''

stitch = '\n'.join(stile(*i) for i in INKS)

html = open(SRC, encoding='utf-8').read()
html = html.replace('__SPECIMENS__', specimens)
html = html.replace('__STITCH__', stitch)

# ── logo: downscale then embed ────────────────────────────────────────────
tmp = '/tmp/_logo_lab.png'
subprocess.run(['sips','-Z','200',f'{ROOT}/app/assets/logo-alpha.png','--out',tmp],
               capture_output=True)
logo_b64 = base64.b64encode(open(tmp,'rb').read()).decode()
html = html.replace('__LOGO__', logo_b64)

# ── fonts: subset to the glyphs this document actually uses ──────────────
text = re.sub(r'<[^>]+>', ' ', html)
chars = set(text) | set('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ.·:’')
chars = {c for c in chars if ord(c) > 31}

FONTS = {
 '__FONT_BHS__'  : 'black-han-sans/400Regular/BlackHanSans_400Regular.ttf',
 '__FONT_OSW__'  : 'oswald/600SemiBold/Oswald_600SemiBold.ttf',
 '__FONT_BODY__' : 'ibm-plex-sans-kr/400Regular/IBMPlexSansKR_400Regular.ttf',
 '__FONT_BODYB__': 'ibm-plex-sans-kr/700Bold/IBMPlexSansKR_700Bold.ttf',
}

for token, rel in FONTS.items():
    path = f'{ROOT}/app/node_modules/@expo-google-fonts/{rel}'
    if not os.path.exists(path):
        print(f'MISSING {path}'); sys.exit(1)
    font = TTFont(path)
    opts = subset.Options()
    opts.layout_features = ['*']; opts.notdef_outline = True
    opts.desubroutinize = True; opts.drop_tables += ['DSIG']
    s = subset.Subsetter(options=opts)
    s.populate(text=''.join(sorted(chars)))
    s.subset(font)
    buf = io.BytesIO()
    font.flavor = 'woff2'
    font.save(buf)
    b64 = base64.b64encode(buf.getvalue()).decode()
    print(f'{token}: {len(buf.getvalue())/1024:.0f}KB -> b64 {len(b64)/1024:.0f}KB')
    html = html.replace(token, b64)

open(OUT,'w',encoding='utf-8').write(html)
print(f'WROTE {OUT}  {len(html)/1024:.0f}KB')
