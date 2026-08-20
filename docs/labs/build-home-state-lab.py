#!/usr/bin/env python3
import base64, io, re, subprocess
from fontTools import subset
from fontTools.ttLib import TTFont
ROOT="/Users/sean/dev/daengrun"; F=f"{ROOT}/docs/labs/home-state-lab.html"
BELL=('<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round">'
 '<path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.7 21a2 2 0 0 1-3.4 0"/></svg>')
A='›'
BAR='<div class="bar"><span>1:19</span><span class="isl"></span><span style="font-size:10px">▮▮</span></div>'
CHROME=(f'<div class="chrome"><div class="bell">{BELL}<i></i></div></div><div class="hair"></div>'
        '<div class="serial">MEMBER SINCE 2026.07</div>')
def drop(wm=False,h=44):
    w=('<div class="wmk">도그스하이</div>' if wm else '')
    return f'<div class="drop"><img src="data:image/png;base64,__LOGO__" style="height:{h}px">{w}</div>'
def hero(color,label,phrase,sub,inline=None,wm=False,mh=44):
    il=f'<div class="inline">{inline} {A}</div>' if inline else ''
    return (f'<div class="hero"><div class="stchip" style="color:{color}">'
      f'<span class="dot" style="background:{color}"></span>{label}</div>'
      f'<div class="phw"><div class="phr">{phrase}</div>{drop(wm,mh)}</div>'
      f'<div class="sub">{sub}</div>{il}</div>')
def cta(l='다음 하이 미리 예약',cls='',size=26):
    return f'<div class="cta {cls}"><b style="font-size:{size}px">{l}</b><span class="arr">{A}</span></div>'

CLUB_WIN=('<div style="margin:14px 16px 0;background:var(--gsoft);border:1px solid #E7DAB6;padding:0;'
 'box-shadow:inset 0 1px 0 rgba(255,255,255,.85)">'
 '<div class="foiledge" style="height:2px"></div>'
 '<div style="padding:15px 16px 13px;display:flex;align-items:center;gap:13px">'
 '<div style="width:42px;height:42px;flex:0 0 42px;border:1.5px solid var(--gsheen);display:flex;'
 'align-items:center;justify-content:center;font-family:\'BHS\',sans-serif;font-size:19px;color:var(--gink)">반</div>'
 '<div style="flex:1;min-width:0">'
 '<div style="font-family:\'BHS\',sans-serif;font-size:20px;color:var(--gink);'
 'text-shadow:0 1px 0 rgba(255,255,255,.95),0 -1px 0 rgba(96,78,32,.25)">반포동 하이클럽</div>'
 '<div style="font-size:13px;color:#8A7434;margin-top:2px">호스트 · 멤버 1명</div></div>'
 f'<span style="color:var(--gink);font-size:19px">{A}</span></div>'
 '<div style="border-top:1px solid #E4D5AE;padding:7px 16px;display:flex;justify-content:space-between">'
 '<span class="mono-sm" style="color:#A08A50">EST. 2026 · 반포</span>'
 '<span class="mono-sm" style="color:#A08A50">멤버 1</span></div></div>')

# ── A/B ──
AB=[]
for tag,ttl,wm,dsc,f1,f2 in [
 ('A','Mark only',False,'The hound alone fills the gap. Cleanest composition — the phrase stays the only word-object on screen.',
  '<b>Brand cost</b> the name 도그스하이 no longer appears on home at all','<b>Bet</b> the mark alone carries recognition (it does on the icon)'),
 ('B','Mark + wordmark',True,'Mark with the wordmark set small beneath it, right-aligned. Fills more of the gap and keeps the name.',
  '<b>Risk</b> a second type object next to a 37pt phrase — quieter, but still an object','<b>Safer</b> for a pre-launch product nobody can name yet')]:
    body=(BAR+CHROME+hero('var(--ready)','확정됨','오늘 3:30<br>초코가 달려요',
      's4kim2025 러너 · 반포 한강 5km','티켓 보기',wm=wm)+cta()+'<div style="height:16px"></div>')
    AB.append(f'<div class="spec"><div class="sh"><span class="sn">{tag}</span><span class="stt">{ttl}</span></div>'
      f'<div class="sd">{dsc}</div><div class="ph">{body}</div><div class="sf"><div>{f1}</div><div>{f2}</div></div></div>')

# ── FULL ──
FULL=(BAR+CHROME
 +hero('var(--ready)','확정됨','오늘 3:30<br>초코가 달려요','s4kim2025 러너 · 반포 한강 5km','티켓 보기')
 +cta()
 +'<div class="kick">동네</div>'+CLUB_WIN
 +'<div style="padding:16px 16px 6px;display:flex;justify-content:space-between;align-items:baseline">'
 '<span style="font-size:15px;font-weight:700;color:var(--ink)">동네 러너</span>'
 f'<span style="font-size:13px;color:var(--pdim)">동네 랭킹 {A}</span></div>'
 '<div class="strip">'
 +''.join(f'<div class="rcard"><div class="nm">{n}</div><div class="mt">{m}</div><div class="st">{r} RUNS · {p}</div></div>'
   for n,m,r,p in [('s4kim2025','인증 러너','4','7\'00"'),('지수','베테랑 · 반포동','87','6\'35"'),('민아','인증 러너','34','7\'12"')])
 +'</div>'
 +'<div style="padding:16px 16px 6px;display:flex;justify-content:space-between;align-items:baseline">'
 '<span style="font-size:15px;font-weight:700;color:var(--ink)">동네 코스</span>'
 f'<span style="font-size:13px;color:var(--pdim)">전체 12개 {A}</span></div>'
 '<div class="strip">'
 +''.join(f'<div class="tile"><div class="km">{k}</div><div class="lb">TRAIL · 포장 {p}</div></div>'
   for k,p in [('1.8K','70%'),('2.4K','100%'),('5.0K','80%')])
 +'</div>'
 +'<div class="kick" style="padding-top:20px">나</div>'
 +'<div style="display:flex;margin:0 16px;border-top:2px solid var(--ink)">'
 '<div style="flex:1;padding:11px 0 5px;border-right:1px solid var(--hair)"><div class="mono-sm" style="color:#999">이번 주</div>'
 '<div class="num" style="font-size:25px;color:var(--ink)">6.2<span style="font-size:13px;color:var(--pdim)">km</span></div></div>'
 '<div style="flex:1;padding:11px 0 5px 14px;border-right:1px solid var(--hair)"><div class="mono-sm" style="color:#999">통산</div>'
 '<div class="num" style="font-size:25px;color:var(--ink)">41<span style="font-size:13px;color:var(--pdim)">회</span></div></div>'
 '<div style="flex:1;padding:11px 0 5px 14px"><div class="mono-sm" style="color:#999">도장</div>'
 '<div class="num" style="font-size:25px;color:var(--gink)">8</div></div></div>'
 +'<div class="row" style="margin-top:6px"><div><div class="t">하이 포인트</div><div class="d">1,240P · 다음 승급까지 760P</div></div>'
 f'<span style="color:#CCC;font-size:19px">{A}</span></div>'
 +'<div class="row"><div><div class="t">크루 피드에 자랑</div><div class="d">지난 러닝 · 사진 3장</div></div>'
 f'<span style="color:#CCC;font-size:19px">{A}</span></div>'
 +'<div class="row" style="border-bottom:1px solid var(--hair)"><div><div class="t">안심 센터</div><div class="d">보험 · 사고 접수 · 러너 인증</div></div>'
 f'<span style="color:#CCC;font-size:19px">{A}</span></div>'
 +'<div style="height:22px"></div>')

# ── STATES ──
STV=[
 ('①','none · 예약 없음','var(--pdim)','비어 있음','오늘은 아직<br>비어 있어요',
  '초코와 달릴 시간을 잡아보세요',None,'','다음 하이 미리 예약','',
  '<b>coral</b> the CTA — nothing else competes','<b>honest</b> empty is stated, not decorated'),
 ('②','searching · 러너 찾는 중','var(--wait)','찾는 중','러너를<br>찾고 있어요',
  '<span class="num">3</span>분째 · 반포 근처 러너 <span class="num">4</span>명에게 요청했어요','레이더 보기','',
  '다음 하이 미리 예약','ink',
  '<b>blue</b> = waiting, per the GO law','<b>CTA is ink</b> — you already have one in flight'),
 ('③','directed · 지명 대기','var(--wait)','응답 대기','응답을<br>기다려요',
  's4kim2025 러너에게 지명 요청 · <span class="num">5</span>분째 · 응답이 없으면 자동으로 다시 찾아요','요청 보기','',
  '다음 하이 미리 예약','ink',
  '<b>rewritten</b> — the runner name moved to the sub line','<b>why</b>: line 1 must clear the mark (see the law)'),
 ('④','confirmed · 확정','var(--ready)','확정됨','오늘 3:30<br>초코가 달려요',
  's4kim2025 러너 · 반포 한강 5km','티켓 보기','',
  '다음 하이 미리 예약','',
  '<b>the one you liked</b> — green state, coral CTA','<b>widest gap</b> — the mark sits easiest here'),
 ('⑤','handoff · 인계','var(--line)','내 차례','지금 만나요<br>반포 3번 출구',
  's4kim2025 러너가 도착했어요 · 초코를 인계해주세요','인계 화면 열기','',
  '다음 하이 미리 예약','ink',
  '<b>coral is the STATE here</b> — so the CTA drops to ink','<b>tightest case</b> — line 1 is long, mark shrinks to 36'),
 ('⑥','active · 러닝 중','var(--volt)','러닝 중','초코가<br>달리고 있어요',
  '<span class="num">2.4</span>km · <span class="num">18</span>분째 · 예상 <span class="num">3:12</span> 도착','지도 보기','',
  '다음 하이 미리 예약','ink',
  '<b>volt</b> = live, the run world\'s own colour','<b>numbers in Oswald</b> — the record voice starts here'),
 ('⑦','done · 완주','var(--gink)','완주','6.2km 완주<br>오늘도 잘 달렸어요',
  '<span class="num">42</span>분 · 페이스 <span class="num">6\'47"</span> · 도장 <span class="num">1</span>개가 찍혔어요','리포트 보기','',
  '다음 하이 미리 예약','',
  '<b>gold ink</b> — the ceremony world signs the end','<b>coral returns</b> to the CTA: your turn again'),
]
STATES=[]
for tag,ttl,col,lab,phr,sub,inl,_x,ctal,ctacls,f1,f2 in STV:
    mh=36 if tag=='⑤' else 44
    body=BAR+CHROME+hero(col,lab,phr,sub,inl,mh=mh)+cta(ctal,ctacls)+'<div style="height:16px"></div>'
    STATES.append(f'<div class="spec"><div class="sh"><span class="sn">{tag}</span><span class="stt">{ttl}</span></div>'
      f'<div class="sd">{sub[:0]}</div>'.replace('<div class="sd"></div>','')
      +f'<div class="ph">{body}</div><div class="sf"><div>{f1}</div><div>{f2}</div></div></div>')

# ── CLUB ITERATION ──
def cw(n,ttl,inner,crit):
    return (f'<div class="cw"><div class="hd"><span class="cn">{n}</span><span class="ct">{ttl}</span></div>'
      f'<div class="stage">{inner}</div><div class="cd">{crit}</div></div>')
G='var(--gsheen)'; GI='var(--gink)'
CL=[]
CL.append(cw('①','Engraved beige (baseline)',
 '<div style="background:var(--gsoft);border:1px solid #E7DAB6;padding:17px;text-align:center;box-shadow:inset 0 1px 0 rgba(255,255,255,.85)">'
 f'<div style="font-family:\'BHS\',sans-serif;font-size:24px;color:{GI};text-shadow:0 1px 0 rgba(255,255,255,.95),0 -1px 0 rgba(96,78,32,.28)">반포동 하이클럽</div>'
 '<div style="font-size:13.5px;color:#8A7434;margin-top:4px">호스트 · 멤버 1명</div></div>',
 '<b>Verdict: a plaque, not a thing you own.</b> Centred and symmetric, so it reads as a sign on a wall. No serial, no date, nothing that says it is <i>yours</i>.'))
CL.append(cw('②','Engraved + ledger foot',
 '<div style="background:var(--gsoft);border:1px solid #E7DAB6;box-shadow:inset 0 1px 0 rgba(255,255,255,.85)">'
 f'<div style="padding:16px 16px 13px;text-align:center"><div style="font-family:\'BHS\',sans-serif;font-size:23px;color:{GI};text-shadow:0 1px 0 rgba(255,255,255,.95)">반포동 하이클럽</div>'
 '<div style="font-size:13px;color:#8A7434;margin-top:3px">호스트 · 멤버 1명</div></div>'
 '<div style="border-top:1px solid #E4D5AE;padding:7px 14px;display:flex;justify-content:space-between">'
 '<span class="mono-sm" style="color:#A08A50">EST. 2026 · 반포</span><span class="mono-sm" style="color:#A08A50">NO. —</span></div></div>',
 '<b>Better.</b> The foot rule turns a plaque into a document. The empty NO. is honest but visibly missing — it wants the server field.'))
CL.append(cw('③','Foil edge + monogram (winner)',
 '<div style="background:var(--gsoft);border:1px solid #E7DAB6;box-shadow:inset 0 1px 0 rgba(255,255,255,.85)">'
 '<div class="foiledge" style="height:2px"></div>'
 '<div style="padding:15px 16px 13px;display:flex;align-items:center;gap:13px">'
 f'<div style="width:42px;height:42px;flex:0 0 42px;border:1.5px solid {G};display:flex;align-items:center;justify-content:center;font-family:\'BHS\',sans-serif;font-size:19px;color:{GI}">반</div>'
 f'<div style="flex:1"><div style="font-family:\'BHS\',sans-serif;font-size:20px;color:{GI};text-shadow:0 1px 0 rgba(255,255,255,.95)">반포동 하이클럽</div>'
 '<div style="font-size:13px;color:#8A7434;margin-top:2px">호스트 · 멤버 1명</div></div>'
 f'<span style="color:{GI};font-size:19px">{A}</span></div>'
 '<div style="border-top:1px solid #E4D5AE;padding:7px 16px;display:flex;justify-content:space-between">'
 '<span class="mono-sm" style="color:#A08A50">EST. 2026 · 반포</span><span class="mono-sm" style="color:#A08A50">멤버 1</span></div></div>',
 '<b>Verdict: the one to ship.</b> Asymmetric (monogram left, arrow right) so it reads as a row you enter, not a sign you look at; foil edge gives it a manufactured top; ledger foot gives it provenance. Used in the full screen above.'))
CL.append(cw('④','Night plate + foil',
 '<div style="background:var(--ncard);border:1px solid var(--nedge)">'
 '<div class="foiledge" style="height:3px"></div>'
 '<div style="padding:15px 16px;display:flex;align-items:center;gap:12px">'
 f'<div style="width:40px;height:40px;flex:0 0 40px;border:1px solid {G};display:flex;align-items:center;justify-content:center;font-family:\'BHS\',sans-serif;font-size:18px;color:{G}">반</div>'
 '<div style="flex:1"><div style="font-size:17px;font-weight:700;color:#fff">반포동 하이클럽</div>'
 '<div style="font-size:13px;color:var(--ndim);margin-top:2px">호스트 · 멤버 1명</div></div>'
 f'<span style="color:{G};font-size:18px">{A}</span></div></div>',
 '<b>Strongest object, wrong screen.</b> It wins on presence and instantly re-imports the dark island that was retired for competing with the hero. Correct for the club <i>screen</i>, too loud for home.'))
CL.append(cw('⑤','Ticket stub',
 '<div style="background:#fff;border:1px solid #E3E0DA">'
 '<div style="padding:14px 16px 11px"><span class="mono-sm" style="color:#A08A50">CLUB · 반포</span>'
 f'<div style="font-family:\'BHS\',sans-serif;font-size:21px;color:var(--ink);margin-top:6px">반포동 하이클럽</div></div>'
 '<div style="height:1px;background:repeating-linear-gradient(90deg,#DDD 0 6px,transparent 6px 12px)"></div>'
 '<div style="padding:9px 16px;display:flex;justify-content:space-between;align-items:center">'
 '<span style="font-size:13px;color:var(--pdim)">호스트 · 멤버 1명</span>'
 f'<span style="font-size:13.5px;font-weight:700;color:var(--ink)">세션 열기 {A}</span></div></div>',
 '<b>Collides.</b> The perforation is already the booking ticket\'s device — using it twice on one screen makes neither ticket special. Hold this for a club session pass.'))
CL.append(cw('⑥','Deep letterpress, no colour',
 '<div style="background:#F3F1EC;border:1px solid #E2DED5;padding:18px 16px;box-shadow:inset 0 2px 4px rgba(120,110,90,.10)">'
 '<div style="font-family:\'BHS\',sans-serif;font-size:23px;color:#6E6A5F;text-shadow:0 1px 0 rgba(255,255,255,.95),0 -1px 1px rgba(80,74,60,.25)">반포동 하이클럽</div>'
 '<div style="font-size:13px;color:#8B8579;margin-top:4px">호스트 · 멤버 1명</div></div>',
 '<b>Elegant and forgettable.</b> Removing gold removes the only thing that said "club". Reads as a disabled row — grey debossed text is the universal signal for <i>unavailable</i>.'))
CL.append(cw('⑦','Wax seal',
 '<div style="background:var(--gsoft);border:1px solid #E7DAB6;padding:15px 16px;display:flex;align-items:center;gap:14px">'
 '<div style="width:46px;height:46px;flex:0 0 46px;border-radius:24px;background:radial-gradient(circle at 35% 30%,#C0562F,#8E3A1E);'
 'display:flex;align-items:center;justify-content:center;font-family:\'BHS\',sans-serif;font-size:17px;color:#F6E3D5;transform:rotate(-6deg)">반</div>'
 f'<div style="flex:1"><div style="font-family:\'BHS\',sans-serif;font-size:20px;color:{GI}">반포동 하이클럽</div>'
 '<div style="font-size:13px;color:#8A7434;margin-top:2px">호스트 · 멤버 1명</div></div></div>',
 '<b>Breaks the colour law.</b> The wax reads coral-adjacent, so the frame now has two warm saturated objects and the CTA loses. Also: a seal means <i>sealed/finished</i> in this product — wrong verb for a place you enter.'))
CL.append(cw('⑧','Foil rule, name only',
 '<div style="background:var(--soft);padding:14px 2px">'
 '<div class="foiledge" style="height:2px;margin-bottom:11px"></div>'
 '<div style="display:flex;align-items:baseline;justify-content:space-between">'
 f'<span style="font-family:\'BHS\',sans-serif;font-size:22px;color:var(--ink)">반포동 하이클럽</span>'
 f'<span style="font-size:13.5px;color:var(--pdim)">멤버 1 {A}</span></div></div>',
 '<b>The minimal that actually works.</b> No box at all — a foil rule and a name, matching the screen\'s "선 0개, 상자 0개" grammar. Loses the object-ness of ③ but never fights the hero. <b>The real alternative.</b>'))
CL.append(cw('⑨','Corner-fold card',
 '<div style="background:var(--gsoft);border:1px solid #E7DAB6;padding:15px 16px;position:relative;overflow:hidden">'
 f'<div style="position:absolute;top:0;right:0;width:26px;height:26px;background:linear-gradient(225deg,{G} 50%,transparent 50%)"></div>'
 f'<div style="font-family:\'BHS\',sans-serif;font-size:20px;color:{GI}">반포동 하이클럽</div>'
 '<div style="font-size:13px;color:#8A7434;margin-top:3px">호스트 · 멤버 1명</div></div>',
 '<b>Decoration pretending to be structure.</b> The fold means nothing — nothing is folded, nothing opens. Under the honesty laws a device that implies an affordance it does not have is the visual version of a dead button.'))
CL.append(cw('⑩','Two-line ledger, no plate',
 '<div style="background:var(--soft);padding:12px 2px">'
 '<div style="display:flex;justify-content:space-between;align-items:baseline;border-bottom:1px solid #E4D5AE;padding-bottom:7px">'
 f'<span style="font-family:\'BHS\',sans-serif;font-size:19px;color:{GI}">반포동 하이클럽</span>'
 '<span class="mono-sm" style="color:#A08A50">EST. 2026</span></div>'
 '<div style="display:flex;justify-content:space-between;padding-top:7px">'
 '<span style="font-size:13px;color:#8A7434">호스트 · 멤버 1명</span>'
 f'<span style="font-size:13px;font-weight:700;color:{GI}">세션 열기 {A}</span></div></div>',
 '<b>Closest to the record thesis.</b> A ledger entry rather than a card — gold ink and a hairline do all the work. Weakest as an <i>object</i>, strongest as <i>evidence</i>. Pairs best with ⑧ if you want home to stay flat.'))

html=open(F,encoding='utf-8').read()
html=html.replace('__AB__','\n'.join(AB)).replace('__FULL__',
  f'<div class="spec" style="width:402px"><div class="ph">{FULL}</div></div>')
html=html.replace('__STATES__','\n'.join(STATES)).replace('__CLUBS__','\n'.join(CL))
tmp='/tmp/_logo_s.png'
subprocess.run(['sips','-Z','220',f'{ROOT}/app/assets/logo-alpha.png','--out',tmp],capture_output=True)
html=html.replace('__LOGO__',base64.b64encode(open(tmp,'rb').read()).decode())
text=re.sub(r'<[^>]+>',' ',html)
chars={c for c in set(text)|set('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ.·’—①②③④⑤⑥⑦⑧⑨⑩▮') if ord(c)>31}
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
