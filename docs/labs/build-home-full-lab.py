#!/usr/bin/env python3
import base64, io, re, subprocess
from fontTools import subset
from fontTools.ttLib import TTFont
ROOT="/Users/sean/dev/daengrun"; F=f"{ROOT}/docs/labs/home-full-lab.html"
A='›'
BELL=('<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round">'
 '<path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.7 21a2 2 0 0 1-3.4 0"/></svg>')
def S(inner,w=150,h=110,op=.15,sw=2):
    return (f'<div class="art" style="opacity:{op}"><svg width="{w}" height="{h}" viewBox="0 0 {w} {h}" fill="none" '
            f'stroke="currentColor" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round">{inner}</svg></div>')
def Ssm(inner,w=110,h=64,op=.14,sw=1.8):
    return (f'<div class="art" style="opacity:{op}"><svg width="{w}" height="{h}" viewBox="0 0 {w} {h}" fill="none" '
            f'stroke="currentColor" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round">{inner}</svg></div>')
D_DOG=S('<path d="M8 74c18 2 26-14 44-16s26 10 42 4 22-22 38-22"/><path d="M18 74l-8 16M46 66l-6 20M78 62l-4 22M108 58l-2 22"/>')
D_CAL=S('<rect x="16" y="24" width="112" height="70"/><path d="M16 44h112M40 24v-12M104 24v-12"/>'
        '<path d="M40 60h14M68 60h14M96 60h14M40 78h14M68 78h14"/>')
D_TICKET=S('<path d="M14 26h120v24a10 10 0 0 0 0 20v24H14V70a10 10 0 0 0 0-20z"/>'
           '<path d="M74 26v8M74 44v8M74 62v8M74 80v8" stroke-dasharray="1 7"/>')
D_LEASH=S('<path d="M10 30c26 0 30 26 52 26s34-30 60-30"/><circle cx="10" cy="30" r="6"/>'
          '<path d="M122 26c10 0 16 8 16 18s-8 18-18 18"/><path d="M60 62v26M50 88h20"/>')
D_CHAT=S('<rect x="14" y="24" width="104" height="56" rx="8"/><path d="M40 92l14-12h-14z"/><path d="M34 44h64M34 58h44"/>')
D_ELEV=S('<path d="M6 88l26-30 22 20 26-46 24 32 30-24"/><path d="M6 96h128" stroke-dasharray="2 6"/>')
D_COIN=Ssm('<circle cx="66" cy="32" r="20"/><circle cx="66" cy="32" r="12"/><path d="M30 20h14M26 32h18M30 44h14"/>')
D_PHOTO=Ssm('<rect x="24" y="14" width="52" height="40"/><rect x="38" y="22" width="52" height="40"/>'
            '<circle cx="56" cy="36" r="7"/>')
D_SHIELD=Ssm('<path d="M64 10l26 9v20c0 16-12 25-26 30-14-5-26-14-26-30V19z"/><path d="M54 38l8 8 16-16"/>')

def btn(cls,t,d,art='',sm=False,dot=False,sheen=False):
    k='btn'+(' sm' if sm else '')+(' sheen' if sheen else '')+(' '+cls if cls else '')
    dd=f'<span class="ldot"></span>' if dot else ''
    return (f'<div class="{k}">{art}<div><div class="t">{dd}{t}</div><div class="d">{d}</div></div>'
            f'<div class="arr">{A}</div></div>')
def hero(col,lab,phr,sub,mh=58):
    return ('<div class="hero"><div class="stchip" style="color:'+col+'">'
      f'<span class="dot" style="background:{col}"></span>{lab}</div>'
      f'<div class="phw"><div class="phr">{phr}</div>'
      f'<div class="drop"><img src="data:image/png;base64,__LOGO__" style="height:{mh}px"></div></div>'
      f'<div class="sub">{sub}</div></div>')
TOP=('<div class="bar"><span>1:19</span><span class="isl"></span><span style="font-size:10px">▮▮</span></div>'
 f'<div class="tl"><div class="sp"></div><div class="wm">도그스하이</div><div class="bl">{BELL}<i></i></div></div>')

CLUB=('<div class="kick">동네</div><div class="club">'
 '<div class="foiledge" style="height:2px"></div>'
 '<div style="padding:14px 16px 12px;display:flex;align-items:center;gap:13px">'
 '<div style="width:40px;height:40px;flex:0 0 40px;border:1.5px solid var(--gsheen);display:flex;'
 'align-items:center;justify-content:center;font-family:\'BHS\',sans-serif;font-size:18px;color:var(--gink)">반</div>'
 '<div style="flex:1"><div style="font-family:\'BHS\',sans-serif;font-size:19px;color:var(--gink);'
 'text-shadow:0 1px 0 rgba(255,255,255,.95)">반포동 하이클럽</div>'
 '<div style="font-size:13px;color:#8A7434;margin-top:2px">호스트 · 멤버 1명이 함께해요</div></div>'
 f'<span style="color:var(--gink);font-size:19px">{A}</span></div>'
 '<div style="border-top:1px solid #E4D5AE;padding:6px 16px;display:flex;justify-content:space-between">'
 '<span class="mono-sm" style="color:#A08A50">EST. 2026 · 반포</span>'
 '<span class="mono-sm" style="color:#A08A50">멤버 1</span></div></div>')
RUNNERS=(f'<div class="modh"><span class="t">동네 러너</span><span class="l">동네 랭킹 {A}</span></div><div class="strip">'
 +''.join(f'<div class="rcard"><div class="nm">{n}</div><div class="mt">{m}</div><div class="st">{r} RUNS · {p}</div></div>'
   for n,m,r,p in [('s4kim2025','인증 러너','4','7\'00"'),('지수','베테랑 · 반포동','87','6\'35"'),('민아','인증 러너','34','7\'12"')])
 +'</div>')
COURSES=(f'<div class="modh"><span class="t">동네 코스</span><span class="l">전체 12개 {A}</span></div><div class="strip">'
 +''.join(f'<div class="tile"><div class="km">{k}</div><div class="lb">TRAIL · 포장 {p}</div></div>'
   for k,p in [('1.8K','70%'),('2.4K','100%'),('5.0K','80%')])+'</div>'
 +'<div style="padding:10px 16px 0">'+btn('g-paper','코스 둘러보기','반포 근처 코스 12개를 볼 수 있어요',D_ELEV,sm=True)+'</div>')
ME=('<div class="kick">나</div>'
 '<div class="recrow">'
 '<div><div class="mono-sm" style="color:#999">이번 주</div><div class="num" style="font-size:25px;color:var(--ink)">6.2<span style="font-size:13px;color:var(--pdim)">km</span></div></div>'
 '<div><div class="mono-sm" style="color:#999">통산</div><div class="num" style="font-size:25px;color:var(--ink)">41<span style="font-size:13px;color:var(--pdim)">회</span></div></div>'
 '<div><div class="mono-sm" style="color:#999">도장</div><div class="num" style="font-size:25px;color:var(--gink)">8</div></div></div>'
 '<div style="padding:12px 16px 0;display:grid;gap:9px">'
 +btn('g-gold ink-gold','하이 포인트','1,240P · 다음 승급까지 760P 남았어요',D_COIN,sm=True)
 +btn('g-lilac ink-lilac','크루 피드에 자랑','지난 러닝 사진 3장을 올릴 수 있어요',D_PHOTO,sm=True)
 +btn('g-blue ink-blue','안심 센터','보험과 사고 접수, 러너 인증을 확인해요',D_SHIELD,sm=True)
 +'</div>'
 '<div class="foot"><span class="num" style="font-size:11px;letter-spacing:1.6px;color:var(--pdim)">MEMBER SINCE 2026.07</span></div>')
TAIL=CLUB+RUNNERS+COURSES+ME

NONE=(TOP+hero('var(--pdim)','비어 있음','오늘은 아직<br>비어 있어요','초코와 달릴 시간을 잡아보세요')
 +'<div class="opts">'
 +btn('b-pri','지금 찾기','지금 뛸 수 있는 러너 <b style="color:#fff">4명</b>이 근처에 있어요',D_DOG,dot=True,sheen=True)
 +btn('g-paper','미리 예약','날짜와 시간을 골라 잡아둬요',D_CAL)
 +'</div>'+TAIL)
CONF=(TOP+hero('var(--ready)','확정됨','오늘 3:30<br>초코가 달려요','s4kim2025 러너 · 반포 한강 5km')
 +'<div class="opts">'
 +btn('g-gold ink-gold','티켓 보기','시간과 장소, 러너를 확인해요',D_TICKET)
 +btn('g-lilac ink-lilac','채팅','러너에게 물어볼 게 있다면 편하게 물어보세요',D_CHAT,sm=True)
 +btn('g-paper','미리 예약','날짜와 시간을 골라 잡아둬요',D_CAL,sm=True)
 +'</div>'+TAIL)
HAND=(TOP+hero('var(--cor)','내 차례','지금 만나요<br>반포 3번 출구','s4kim2025 러너가 도착했어요 · 초코를 인계해주세요',mh=42)
 +'<div class="opts">'
 +btn('b-pri','인계하기','러너에게 아이를 넘기고 봉인해요',D_LEASH,dot=True)
 +btn('g-lilac ink-lilac','채팅','늦거나 못 찾겠다면 바로 알려주세요',D_CHAT,sm=True)
 +'</div>'+TAIL)

FAN=[('none','예약 없음',NONE,
   '<b>Coral first, drawn dog, dot on real availability.</b> 미리 예약 sits directly under it at full height — the only state with two full-size decisions.'),
  ('confirmed','확정',CONF,
   '<b>No coral at all.</b> Nothing is urgent, so the ticket takes the gold wash and 채팅/미리 예약 drop to short rows. This is the longest column — see note 4.'),
  ('handoff','인계',HAND,
   '<b>Coral returns, 미리 예약 vanishes.</b> One decision plus an escape hatch. The leash drawing and the dot both point at a runner who is physically waiting.')]
html=open(F,encoding='utf-8').read()
html=html.replace('__FAN__','\n'.join(
  f'<div class="col"><div class="lab"><span class="n">{n}</span><span class="t">{t}</span></div>'
  f'<div class="ph">{b}</div><div class="note">{nt}</div></div>' for n,t,b,nt in FAN))
tmp='/tmp/_logo_f.png'
subprocess.run(['sips','-Z','260',f'{ROOT}/app/assets/logo-alpha.png','--out',tmp],capture_output=True)
html=html.replace('__LOGO__',base64.b64encode(open(tmp,'rb').read()).decode())
text=re.sub(r'<[^>]+>',' ',html)
chars={c for c in set(text)|set('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ.·’—▮%,') if ord(c)>31}
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
