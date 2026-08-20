#!/usr/bin/env python3
import base64, io, re, subprocess
from fontTools import subset
from fontTools.ttLib import TTFont
ROOT="/Users/sean/dev/daengrun"; F=f"{ROOT}/docs/labs/home-v3-lab.html"
BELL=('<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round">'
 '<path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.7 21a2 2 0 0 1-3.4 0"/></svg>')
A='›'
BAR='<div class="bar"><span>1:19</span><span class="isl"></span><span style="font-size:10px">▮▮</span></div>'
TL=(f'<div class="tl"><div class="sp"></div><div class="wm">도그스하이</div>'
    f'<div class="bl">{BELL}<i></i></div></div>')
def hero(col,lab,phr,sub,inline=None,mh=58):
    il=f'<div class="inline">{inline} {A}</div>' if inline else ''
    return (f'<div class="hero"><div class="stchip" style="color:{col}">'
      f'<span class="dot" style="background:{col}"></span>{lab}</div>'
      f'<div class="phw"><div class="phr">{phr}</div>'
      f'<div class="drop"><img src="data:image/png;base64,__LOGO__" style="height:{mh}px"></div></div>'
      f'<div class="sub">{sub}</div>{il}</div>')
def opt(t,d,a=True,size=24):
    cls='optA' if a else 'optB'
    return (f'<div class="opt {cls}"><div><div class="t" style="font-size:{size}px">{t}</div>'
            f'<div class="d">{d}</div></div><div class="arr">{A}</div></div>')
def quiet(t,d):
    return (f'<div class="quiet"><div><div class="t">{t}</div><div class="d">{d}</div></div>'
            f'<span style="color:#CCC;font-size:19px">{A}</span></div>')
def opts(*inner): return '<div class="opts">'+''.join(inner)+'</div>'

NONE=(BAR+TL+hero('var(--pdim)','비어 있음','오늘은 아직<br>비어 있어요','초코와 달릴 시간을 잡아보세요')
 +opts(opt('지금 찾기','지금 뛸 수 있는 러너를 바로',True),
       opt('미리 예약','날짜와 시간을 골라',False))
 +'<div style="height:18px"></div>')

ST=[
 ('none','예약 없음',NONE,'coral 지금 찾기 · ink 미리 예약',
  '<b>primary</b> 지금 찾기 → /owner/request?now=1','<b>the only coral</b> — your turn to book'),
 ('searching','러너 찾는 중',
  BAR+TL+hero('var(--wait)','찾는 중','러너를<br>찾고 있어요',
   '<span class="num">3</span>분째 · 반포 근처 러너 <span class="num">4</span>명에게 요청했어요')
  +opts(opt('레이더 보기','누구에게 요청이 갔는지',False))
  +quiet('미리 예약','다른 날짜도 잡아둘 수 있어요')+'<div style="height:18px"></div>',
  'ink 레이더 보기 · 예약은 조용한 행으로',
  '<b>primary</b> 레이더 보기 → /owner/radar','<b>no coral</b> — nothing here is your turn'),
 ('directed','지명 대기',
  BAR+TL+hero('var(--wait)','응답 대기','응답을<br>기다려요',
   's4kim2025 러너에게 지명 요청 · <span class="num">5</span>분째')
  +opts(opt('요청 보기','응답이 없으면 자동으로 다시 찾아요',False))
  +quiet('미리 예약','다른 날짜도 잡아둘 수 있어요')+'<div style="height:18px"></div>',
  'ink 요청 보기','<b>primary</b> 요청 보기 → /owner/matching','<b>same blue</b> — copy carries the difference'),
 ('confirmed','확정',
  BAR+TL+hero('var(--ready)','확정됨','오늘 3:30<br>초코가 달려요','s4kim2025 러너 · 반포 한강 5km')
  +opts(opt('티켓 보기','시간 · 장소 · 러너',False))
  +quiet('채팅','러너에게 물어볼 게 있다면')
  +quiet('미리 예약','다른 날짜도 잡아둘 수 있어요')+'<div style="height:18px"></div>',
  'ink 티켓 보기 · 채팅/예약은 행',
  '<b>primary</b> 티켓 보기 → /owner/schedule','<b>green state</b>, ink CTA — nothing urgent yet'),
 ('handoff','인계 ← 당신 질문',
  BAR+TL+hero('var(--cor)','내 차례','지금 만나요<br>반포 3번 출구',
   's4kim2025 러너가 도착했어요 · 초코를 인계해주세요')
  +opts(opt('인계하기','러너에게 아이를 넘기고 봉인해요',True))
  +quiet('채팅','늦거나 못 찾겠다면')+'<div style="height:18px"></div>',
  'CORAL 인계하기 — 예약 버튼은 사라짐',
  '<b>primary</b> 인계하기 → /owner/meetup (존재)','<b>the loudest moment</b> — 예약은 여기서 방해다'),
 ('active','러닝 중',
  BAR+TL+hero('var(--volt)','러닝 중','초코가<br>달리고 있어요',
   '<span class="num">2.4</span>km · <span class="num">18</span>분째 · 예상 <span class="num">3:12</span> 도착')
  +opts(opt('지도 보기','실시간 위치와 거리',False))+'<div style="height:18px"></div>',
  'ink 지도 보기 — 그 외 없음',
  '<b>primary</b> 지도 보기 → /owner/live','<b>deliberately sparse</b> — 지금은 지켜보는 시간'),
 ('done','완주',
  BAR+TL+hero('var(--gink)','완주','6.2km 완주<br>오늘도 잘 달렸어요',
   '<span class="num">42</span>분 · 페이스 <span class="num">6\'47"</span> · 도장 <span class="num">1</span>개')
  +opts(opt('리포트 보기','기록 · 사진 · 도장',True),
        opt('미리 예약','다음 하이를 잡아둬요',False))
  +'<div style="height:18px"></div>',
  'coral 리포트 · ink 예약',
  '<b>primary</b> 리포트 보기 → /owner/report','<b>coral returns</b> — 볼 차례이자 다시 잡을 차례'),
]
CLUB=('<div style="margin:14px 16px 0;background:var(--gsoft);border:1px solid #E7DAB6">'
 '<div class="foiledge" style="height:2px"></div>'
 '<div style="padding:14px 16px 12px;display:flex;align-items:center;gap:13px">'
 '<div style="width:40px;height:40px;flex:0 0 40px;border:1.5px solid var(--gsheen);display:flex;'
 'align-items:center;justify-content:center;font-family:\'BHS\',sans-serif;font-size:18px;color:var(--gink)">반</div>'
 '<div style="flex:1"><div style="font-family:\'BHS\',sans-serif;font-size:19px;color:var(--gink);'
 'text-shadow:0 1px 0 rgba(255,255,255,.95)">반포동 하이클럽</div>'
 '<div style="font-size:13px;color:#8A7434;margin-top:2px">호스트 · 멤버 1명</div></div>'
 f'<span style="color:var(--gink);font-size:19px">{A}</span></div>'
 '<div style="border-top:1px solid #E4D5AE;padding:6px 16px;display:flex;justify-content:space-between">'
 '<span class="mono-sm" style="color:#A08A50">EST. 2026 · 반포</span>'
 '<span class="mono-sm" style="color:#A08A50">멤버 1</span></div></div>')
FULL=(BAR+TL+hero('var(--ready)','확정됨','오늘 3:30<br>초코가 달려요','s4kim2025 러너 · 반포 한강 5km')
 +opts(opt('티켓 보기','시간 · 장소 · 러너',False))
 +quiet('채팅','러너에게 물어볼 게 있다면')
 +quiet('미리 예약','다른 날짜도 잡아둘 수 있어요')
 +'<div class="kick">동네</div>'+CLUB
 +'<div style="padding:16px 16px 6px;display:flex;justify-content:space-between;align-items:baseline">'
 '<span style="font-size:15px;font-weight:700;color:var(--ink)">동네 러너</span>'
 f'<span style="font-size:13px;color:var(--pdim)">동네 랭킹 {A}</span></div><div class="strip">'
 +''.join(f'<div class="rcard"><div class="nm">{n}</div><div class="mt">{m}</div><div class="st">{r} RUNS · {p}</div></div>'
   for n,m,r,p in [('s4kim2025','인증 러너','4','7\'00"'),('지수','베테랑 · 반포동','87','6\'35"'),('민아','인증 러너','34','7\'12"')])
 +'</div>'
 +'<div style="padding:16px 16px 6px;display:flex;justify-content:space-between;align-items:baseline">'
 '<span style="font-size:15px;font-weight:700;color:var(--ink)">동네 코스</span>'
 f'<span style="font-size:13px;color:var(--pdim)">전체 12개 {A}</span></div><div class="strip">'
 +''.join(f'<div class="tile"><div class="km">{k}</div><div class="lb">TRAIL · 포장 {p}</div></div>'
   for k,p in [('1.8K','70%'),('2.4K','100%'),('5.0K','80%')])+'</div>'
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
 +'<div class="row"><div><div class="t">안심 센터</div><div class="d">보험 · 사고 접수 · 러너 인증</div></div>'
 f'<span style="color:#CCC;font-size:19px">{A}</span></div>'
 +'<div style="padding:14px 16px 20px;display:flex;justify-content:flex-end;border-top:1px solid var(--hair)">'
 '<span class="num" style="font-size:11px;letter-spacing:1.6px;color:var(--pdim)">MEMBER SINCE 2026.07</span></div>')

def spec(tag,ttl,body,dsc,f1,f2):
    return (f'<div class="spec"><div class="sh"><span class="sn">{tag}</span><span class="stt">{ttl}</span></div>'
      f'<div class="sd">{dsc}</div><div class="ph">{body}</div>'
      f'<div class="sf"><div>{f1}</div><div>{f2}</div></div></div>')
html=open(F,encoding='utf-8').read()
html=html.replace('__NONE__',spec('none','예약 없음 · 기준',NONE,
  '당신이 적어준 그대로. 흰 배경 · 상단 가운데 워드마크 · 빨간 선 없음 · 바짝 붙은 상태·문구 · 커진 마크 · v2 버튼(84px).',
  '<b>지금 찾기</b> coral #C6472C — v2 optA 그대로','<b>미리 예약</b> 1.5px 잉크 테두리 — v2 optB 그대로'))
html=html.replace('__STATES__','\n'.join(spec(t,n,b,d,a,c) for t,n,b,d,a,c in ST))
html=html.replace('__FULL__',f'<div class="spec"><div class="ph">{FULL}</div></div>')
tmp='/tmp/_logo_v3.png'
subprocess.run(['sips','-Z','260',f'{ROOT}/app/assets/logo-alpha.png','--out',tmp],capture_output=True)
html=html.replace('__LOGO__',base64.b64encode(open(tmp,'rb').read()).decode())
text=re.sub(r'<[^>]+>',' ',html)
chars={c for c in set(text)|set('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ.·’—▮/?=[]') if ord(c)>31}
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
