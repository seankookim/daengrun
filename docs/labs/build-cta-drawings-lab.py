#!/usr/bin/env python3
import base64, io, re, subprocess
from fontTools import subset
from fontTools.ttLib import TTFont
ROOT="/Users/sean/dev/daengrun"; F=f"{ROOT}/docs/labs/cta-drawings-lab.html"
A='›'
BELL=('<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round">'
 '<path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.7 21a2 2 0 0 1-3.4 0"/></svg>')

def S(inner,w=150,h=110,stroke='currentColor',op=.16,sw=2):
    return (f'<div class="art" style="opacity:{op}"><svg width="{w}" height="{h}" viewBox="0 0 {w} {h}" fill="none" '
            f'stroke="{stroke}" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round">{inner}</svg></div>')
# drawings
D_RADAR=S('<circle cx="86" cy="55" r="14"/><circle cx="86" cy="55" r="30"/><circle cx="86" cy="55" r="46"/>'
          '<circle cx="86" cy="55" r="62"/><path d="M86 55 L138 22"/>')
D_CAL=S('<rect x="16" y="24" width="112" height="70"/><path d="M16 44h112M40 24v-12M104 24v-12"/>'
        '<path d="M40 60h14M68 60h14M96 60h14M40 78h14M68 78h14"/>')
D_TICKET=S('<path d="M14 26h120v24a10 10 0 0 0 0 20v24H14V70a10 10 0 0 0 0-20z"/>'
           '<path d="M74 26v8M74 44v8M74 62v8M74 80v8" stroke-dasharray="1 7"/>')
D_TRACE=S('<path d="M6 84c14-4 20-26 34-30s22 16 34 8 18-32 32-34 26 10 32 6"/>'
          '<circle cx="6" cy="84" r="5"/><circle cx="138" cy="34" r="5"/>')
D_STAMP=S('<circle cx="82" cy="55" r="40"/><circle cx="82" cy="55" r="31" stroke-dasharray="3 6"/>'
          '<path d="M64 55h36M64 45h36M64 65h24"/>')
D_LEASH=S('<path d="M10 30c26 0 30 26 52 26s34-30 60-30"/><circle cx="10" cy="30" r="6"/>'
          '<path d="M122 26c10 0 16 8 16 18s-8 18-18 18"/><path d="M60 62v26M50 88h20"/>')
D_CHAT=S('<rect x="14" y="24" width="104" height="56" rx="8"/><path d="M40 92l14-12h-14z"/>'
         '<path d="M34 44h64M34 58h44"/>')
D_ELEV=S('<path d="M6 88l26-30 22 20 26-46 24 32 30-24"/><path d="M6 96h128" stroke-dasharray="2 6"/>')
D_CREST=S('<path d="M82 16l40 14v30c0 24-18 38-40 46-22-8-40-22-40-46V30z"/><path d="M82 42v34M66 58h32"/>')
D_DOG=S('<path d="M8 74c18 2 26-14 44-16s26 10 42 4 22-22 38-22"/><path d="M18 74l-8 16M46 66l-6 20M78 62l-4 22M108 58l-2 22"/>')

BTNS=[
 ('①','지금 찾기 — 코랄 + 개','b-pri sheen','',
  '<span class="ldot"></span>지금 찾기','지금 뛸 수 있는 러너 <b style="color:#fff">4명</b>이 근처에 있어요',D_DOG,
  '<b>The primary.</b> Live dot bound to real availability, running-stride drawing behind, sheen on a 6s clock, and the depth edge. The only saturated fill on the screen.'),
 ('②','미리 예약 — 달력','g-paper','',
  '미리 예약','날짜와 시간을 골라 잡아둬요',D_CAL,
  '<b>Paper tint + ink border.</b> The calendar grid says exactly what the next screen is. Keeps the v2 outline weight so it still reads as the secondary.'),
 ('③','티켓 보기 — 퍼포레이션','g-gold ink-gold','',
  '티켓 보기','시간과 장소, 러너를 확인해요',D_TICKET,
  '<b>Gold wash.</b> The perforated stub is drawn, not implied — this is the one button whose destination is literally a ticket, so the drawing is a preview.'),
 ('④','레이더 보기 — 링','g-blue ink-blue','',
  '레이더 보기','요청이 누구에게 갔는지 볼 수 있어요',D_RADAR,
  '<b>Blue wash = waiting</b>, per the colour law. The rings are the radar screen\'s own animation, frozen as line art.'),
 ('⑤','인계하기 — 리드','b-pri','',
  '<span class="ldot"></span>인계하기','러너에게 아이를 넘기고 봉인해요',D_LEASH,
  '<b>The other coral.</b> Handoff is the only other moment that earns a saturated fill and a live dot — the runner really is standing there. Leash drawing, no sheen: this one is urgent, not inviting.'),
 ('⑥','지도 보기 — 트레이스','g-volt ink-volt','',
  '지도 보기','지금 어디를 달리는지 볼 수 있어요',D_TRACE,
  '<b>Volt = the run world.</b> A GPS polyline with endpoints. This is the drawing that best proves the rule: the picture is the thing you will see when you tap.'),
 ('⑦','리포트 보기 — 도장','g-gold ink-gold','',
  '리포트 보기','기록과 사진, 도장을 확인해요',D_STAMP,
  '<b>Stamp with a dashed inner ring.</b> Gold wash ties it to the passport world where the report actually lands.'),
 ('⑧','채팅 — 말풍선','g-lilac ink-lilac','',
  '채팅','러너에게 물어볼 게 있다면 편하게 물어보세요',D_CHAT,
  '<b>Lilac inset.</b> The quietest ground in the system, correct for a support action that should never compete with the booking flow.'),
 ('⑨','코스 둘러보기 — 고도','g-paper','',
  '코스 둘러보기','반포 근처 코스 12개를 볼 수 있어요',D_ELEV,
  '<b>Elevation profile.</b> Says "these are real measured routes" in one line — which is the truest thing about the catalog and the hardest to say in words.'),
 ('⑩','하이클럽 — 크레스트','g-night','',
  '반포동 하이클럽','호스트 · 멤버 1명이 함께해요',D_CREST,
  '<b>The one dark button.</b> Night ground + crest, gold-free so it does not fight ③⑦. Use only if the club stays a button rather than the engraved widget.'),
]
def btn(cls,extra,t,d,art):
    return (f'<div class="btn {cls}" {extra}>{art}<div><div class="t">{t}</div><div class="d">{d}</div></div>'
            f'<div class="arr">{A}</div></div>')
GAL='\n'.join(
 f'<div class="bw"><div class="hd"><span class="n">{n}</span><span class="t">{ttl}</span></div>'
 f'<div class="stage">{btn(c,e,t,d,art)}</div><div class="cd">{crit}</div></div>'
 for n,ttl,c,e,t,d,art,crit in BTNS)

DOTS=[
 ('A','러너 있음 · 4명','b-pri','<span class="ldot"></span>지금 찾기',
  '지금 뛸 수 있는 러너 <b style="color:#fff">4명</b>이 근처에 있어요',
  '<b>Dot pulses because it is true.</b> White dot on coral, 2.1s, with a soft ring that expands and fades.'),
 ('B','러너 있음 · 초록 점','b-pri','<span class="ldot gr"></span>지금 찾기',
  '지금 뛸 수 있는 러너 <b style="color:#fff">4명</b>이 근처에 있어요',
  '<b>Green dot = the ready colour</b>, matching the state chip. Reads more literally as "available" but adds a second hue to a coral fill.'),
 ('C','아무도 없음 · 점 없음','b-pri','지금 찾기',
  '지금은 대기 중인 러너가 없어요 — 예약해두면 먼저 연결해드려요',
  '<b>The honest empty.</b> No dot, no pulse, and the subline says why. This state is what makes the dot believable in A and B.'),
]
DGAL='\n'.join(
 f'<div class="bw"><div class="hd"><span class="n">{n}</span><span class="t">{ttl}</span></div>'
 f'<div class="stage">{btn(c,"",t,d,"")}</div><div class="cd">{crit}</div></div>'
 for n,ttl,c,t,d,crit in DOTS)

PHONE=('<div class="bar"><span>1:19</span><span class="isl"></span><span style="font-size:10px">▮▮</span></div>'
 f'<div class="tl"><div class="sp"></div><div class="wm">도그스하이</div><div class="bl">{BELL}<i></i></div></div>'
 '<div class="hero"><div class="stchip" style="color:var(--pdim)">'
 '<span class="dot" style="background:var(--pdim)"></span>비어 있음</div>'
 '<div class="phw"><div class="phr">오늘은 아직<br>비어 있어요</div>'
 '<div class="drop"><img src="data:image/png;base64,__LOGO__" style="height:58px"></div></div>'
 '<div class="sub">초코와 달릴 시간을 잡아보세요</div></div>'
 '<div class="opts">'
 +btn('b-pri sheen','','<span class="ldot"></span>지금 찾기',
      '지금 뛸 수 있는 러너 <b style="color:#fff">4명</b>이 근처에 있어요',D_DOG)
 +btn('g-paper','','미리 예약','날짜와 시간을 골라 잡아둬요',D_CAL)
 +btn('g-paper','','코스 둘러보기','반포 근처 코스 12개를 볼 수 있어요',D_ELEV)
 +'</div><div style="height:20px"></div>')

html=open(F,encoding='utf-8').read().replace('__BUTTONS__',GAL).replace('__DOTS__',DGAL)
html=html.replace('__PHONE__',f'<div class="spec"><div class="ph">{PHONE}</div></div>')
tmp='/tmp/_logo_d.png'
subprocess.run(['sips','-Z','260',f'{ROOT}/app/assets/logo-alpha.png','--out',tmp],capture_output=True)
html=html.replace('__LOGO__',base64.b64encode(open(tmp,'rb').read()).decode())
text=re.sub(r'<[^>]+>',' ',html)
chars={c for c in set(text)|set('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ.·’—▮%') if ord(c)>31}
FONTS={'__FONT_BHS__':'black-han-sans/400Regular/BlackHanSans_400Regular.ttf',
 '__FONT_OSW__':'oswald/600SemiBold/Oswald_600SemiBold.ttf',
 '__FONT_BODY__':'ibm-plex-sans-kr/400Regular/IBMPlexSansKR_400Regular.ttf',
 '__FONT_BODYB__':'ibm-plex-sans-kr/700Bold/IBMPlexSansKR_700Bold.ttf'}
for tok,rel in FONTS.items():
    f=TTFont(f'{ROOT}/app/node_modules/@expo-google-fonts/{rel}')
    o=subset.Options(); o.layout_features=['*']; o.notdef_outline=True; o.desubroutinize=True
    s=subset.Subsetter(options=o); s.populate(text=''.join(sorted(chars))); s.subset(f)
    b=io.BytesIO(); f.flavor='woff2'; f.save(b)
    print(tok,len(b.getvalue())//1024,'KB'); html=html.replace(tok,base64.b64encode(b.getvalue()).decode())
open(F,'w',encoding='utf-8').write(html); print('WROTE',len(html)//1024,'KB')
