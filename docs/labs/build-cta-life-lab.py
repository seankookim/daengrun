#!/usr/bin/env python3
import base64, io, re, subprocess
from fontTools import subset
from fontTools.ttLib import TTFont
ROOT="/Users/sean/dev/daengrun"; F=f"{ROOT}/docs/labs/cta-life-lab.html"
A='›'
BELL=('<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round">'
 '<path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.7 21a2 2 0 0 1-3.4 0"/></svg>')
def btn(cls='',t='지금 찾기',d='지금 뛸 수 있는 러너를 바로 찾아드려요',ink=False):
    k='btn ink' if ink else 'btn'
    return (f'<div class="{k} {cls}"><div><div class="t">{t}</div><div class="d">{d}</div></div>'
            f'<div class="arr">{A}</div></div>')
B=[
 ('①','플랫 (기준)','', '<b>Verdict: dead on arrival.</b> It is a coloured rectangle. Nothing says it can be pressed — the only affordance is that we all learned rectangles are buttons.'),
 ('②','깊이 · Depth','b-depth','<b>The cheapest real win.</b> A 4px darker edge makes it a physical key; press and it travels down onto the edge. No loop, no battery, works under reduced-motion, and it is the one treatment that reads as pressable while standing still.'),
 ('③','시닌 · Sheen','b-sheen','<b>Ties to the brand.</b> The foil sweep is already our vocabulary (club, passport, receipt). Slow at 5.2s so it reads as light catching an object, not as a loading bar. Risk: on a big flat fill it can look like a skeleton shimmer if sped up — do not go under 4s.'),
 ('④','화살표 넛지','b-nudge','<b>Directional, not decorative.</b> The arrow leans right once per cycle — it says <i>this way</i> rather than <i>look at me</i>. Cheapest possible motion, and the only one that carries meaning about where the tap leads.'),
 ('⑤','그라데이션','b-grad','<b>More colour, as asked — but flat-footed.</b> The gradient adds richness and nothing else; it is warmth without behaviour. Good as a base under ② or ③, weak alone.'),
 ('⑥','그레인 · Grain','b-grain','<b>Print, not screen.</b> Noise on the coral makes it read as ink on stock, which matches the record thesis. Very subtle at 30% — and it costs nothing at runtime. Pairs well; carries little alone.'),
 ('⑦','호흡 · Breathing','b-breathe','<b>Disqualified, and it is the interesting failure.</b> A shadow that swells is genuinely attractive — and it is exactly the invented urgency the repo bans. A button that throbs when nothing is happening teaches the eye to ignore it.'),
 ('⑧','엣지 라이트','b-edge','<b>Lit from above.</b> A bright top inner-edge and a dark bottom one: the button becomes a solid with a light source. Static, so it costs nothing, and it stacks with ② for real dimensionality.'),
 ('⑨','라이브 도트','b-dot','<b>Wrong word.</b> A pulsing dot means <i>live/recording</i> in this product (run tracking, LIVE pill). Putting it on a booking button borrows a meaning that belongs elsewhere.'),
 ('⑩','추천 조합','b-combo','<b>Ship this.</b> Depth + sheen + arrow nudge on <b>one 6s clock</b>, so it reads as a single gesture instead of three effects competing. Press it: it travels down onto its own edge. Everything decorative stops under reduced-motion; the depth and the press survive.'),
]
BTNS='\n'.join(
 f'<div class="bw"><div class="hd"><span class="n">{n}</span><span class="t">{t}</span></div>'
 f'<div class="stage">{btn(c)}</div><div class="cd">{d}</div></div>' for n,t,c,d in B)

PHONE=('<div class="bar"><span>1:19</span><span class="isl"></span><span style="font-size:10px">▮▮</span></div>'
 f'<div class="tl"><div class="sp"></div><div class="wm">도그스하이</div><div class="bl">{BELL}<i></i></div></div>'
 '<div class="hero"><div class="stchip" style="color:var(--pdim)">'
 '<span class="dot" style="background:var(--pdim)"></span>비어 있음</div>'
 '<div class="phw"><div class="phr">오늘은 아직<br>비어 있어요</div>'
 '<div class="drop"><img src="data:image/png;base64,__LOGO__" style="height:58px"></div></div>'
 '<div class="sub">초코와 달릴 시간을 잡아보세요</div></div>'
 '<div class="opts">'
 +btn('b-combo','지금 찾기','지금 뛸 수 있는 러너를 바로 찾아드려요')
 +btn('b-depth','미리 예약','날짜와 시간을 골라 잡아둬요',ink=True)
 +'</div><div style="height:20px"></div>')

html=open(F,encoding='utf-8').read().replace('__BUTTONS__',BTNS)
html=html.replace('__PHONE__',f'<div class="spec"><div class="ph">{PHONE}</div></div>')
tmp='/tmp/_logo_c.png'
subprocess.run(['sips','-Z','260',f'{ROOT}/app/assets/logo-alpha.png','--out',tmp],capture_output=True)
html=html.replace('__LOGO__',base64.b64encode(open(tmp,'rb').read()).decode())
text=re.sub(r'<[^>]+>',' ',html)
chars={c for c in set(text)|set('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ.·’—▮') if ord(c)>31}
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
