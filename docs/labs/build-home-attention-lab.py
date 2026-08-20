#!/usr/bin/env python3
import base64, io, re, subprocess
from fontTools import subset
from fontTools.ttLib import TTFont
ROOT="/Users/sean/dev/daengrun"; F=f"{ROOT}/docs/labs/home-attention-lab.html"

BELL=('<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round">'
 '<path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.7 21a2 2 0 0 1-3.4 0"/></svg>')
A='›'
BAR='<div class="bar"><span>1:19</span><span class="isl"></span><span style="font-size:10px">▮▮</span></div>'
def mast(hair=True,serial=True,wm=20):
    h='<div class="hair"></div>' if hair else ''
    s=('<div class="serial"><span style="flex:1"></span><span>MEMBER SINCE 2026.07</span></div>') if serial else ''
    return (f'<div class="mast"><div class="sp44"></div><div class="lg">'
      f'<img src="data:image/png;base64,__LOGO__" style="height:27px">'
      f'<span class="wm" style="font-size:{wm}px">도그스하이</span></div>'
      f'<div class="bell">{BELL}<i></i></div></div>{h}{s}')
ST=('<div class="st"><span class="when"><span class="num">8월 4일</span> (화) <span class="num">오후 3:30</span></span>'
    '<span class="who">s4kim2025</span><span class="chip">확정됨</span>'
    f'<span style="color:#BBB;font-size:17px">{A}</span></div>')
def cta(l='다음 하이 미리 예약',out=False,size=27,mt=7):
    c='cta out' if out else 'cta'
    return f'<div class="{c}" style="margin-top:{mt}px"><b style="font-size:{size}px">{l}</b><span class="arr">{A}</span></div>'
CLUB=('<div class="club7"><div class="nm">반포동 하이클럽</div><div class="mt">호스트 · 멤버 1명</div></div>')
def row(t,d='',arrow=True):
    dd=f'<div class="d">{d}</div>' if d else ''
    ar=f'<span style="color:#CCC;font-size:19px">{A}</span>' if arrow else ''
    return f'<div class="row"><div><div class="t">{t}</div>{dd}</div>{ar}</div>'
FOLD='<div class="fold" style="height:26px"></div>'
def below(extra=''):
    return ('<div class="kick">동네</div>'+CLUB+row('동네 코스 둘러보기','반포 · 12개')+extra)

V={}
# ① 한 줄 한 결정
V[1]=(BAR+mast()+
 '<div style="height:10px"></div>'+
 f'<div class="row" style="border-top:none;padding:19px 16px"><div><div class="t" style="font-size:19px">8월 4일 3:30 러닝</div>'
 f'<div class="d"><span style="color:var(--ready);font-weight:700">확정됨</span> · s4kim2025 러너</div></div><span style="color:#CCC;font-size:21px">{A}</span></div>'
 f'<div class="row" style="padding:19px 16px"><div><div class="t disp" style="font-size:25px;color:var(--line)">다음 하이 미리 예약</div></div><span style="color:var(--line);font-size:21px">{A}</span></div>'
 +row('코스 둘러보기','반포 · 12개')+FOLD+below())
# ② 상태 우선
V[2]=(BAR+mast()+
 '<div style="padding:20px 16px 16px">'
 '<div style="display:flex;align-items:center;gap:8px"><span style="width:9px;height:9px;border-radius:5px;background:var(--ready)"></span>'
 '<span class="mono-sm" style="color:var(--ready)">CONFIRMED</span></div>'
 '<div class="disp" style="font-size:38px;color:var(--ink);margin-top:8px">오늘 3:30<br>초코가 달려요</div>'
 '<div style="font-size:15px;color:var(--pdim);margin-top:10px">s4kim2025 러너 · 반포 한강 5km</div>'
 f'<div style="margin-top:14px;display:inline-flex;gap:6px;align-items:center;border-bottom:1.5px solid var(--ink);padding-bottom:3px;font-weight:700;font-size:15px;color:var(--ink)">티켓 보기 {A}</div>'
 '</div>'+cta(out=True,size=22)+FOLD+below())
# ③ 기록 우선
V[3]=(BAR+mast()+
 '<div style="padding:16px 16px 10px"><div class="mono-sm" style="color:var(--faintp)">초코의 기록</div>'
 '<div style="display:flex;align-items:baseline;gap:20px;margin-top:6px">'
 '<div><span class="num" style="font-size:52px;color:var(--ink)">41</span><span class="num" style="font-size:18px;color:var(--pdim)"> 회</span></div>'
 '<div><span class="num" style="font-size:52px;color:var(--ink)">238</span><span class="num" style="font-size:18px;color:var(--pdim)"> km</span></div>'
 '<div><span class="num" style="font-size:52px;color:var(--gink)">8</span><span class="num" style="font-size:18px;color:var(--pdim)"> 도장</span></div>'
 '</div></div>'+ST+cta()+FOLD+below())
# ④ 투 버튼 (⑧ v2 순정)
V[4]=(BAR+mast()+ST+
 f'<div class="cta" style="margin-top:8px;padding:26px 18px"><b style="font-size:31px">지금 찾기</b><span class="arr">{A}</span></div>'
 +cta(out=True,size=26,mt=9)+FOLD+below())
# ⑤ 티켓
V[5]=(BAR+mast(serial=False)+
 '<div style="margin:12px 15px 0;background:#fff;border:1px solid #E3E0DA;position:relative">'
 '<div class="foiledge" style="height:3px"></div>'
 '<div style="padding:14px 16px 12px">'
 '<div style="display:flex;justify-content:space-between"><span class="mono-sm" style="color:var(--gsheen)">RUN TICKET</span>'
 '<span class="mono-sm" style="color:var(--faintp)">MEMBER SINCE 2026.07</span></div>'
 '<div class="disp" style="font-size:29px;color:var(--ink);margin-top:9px">8월 4일 오후 3:30</div>'
 '<div style="font-size:14px;color:var(--pdim);margin-top:5px">s4kim2025 러너 · 초코 · 5km</div></div>'
 '<div style="height:1px;background:repeating-linear-gradient(90deg,#DDD 0 6px,transparent 6px 12px);position:relative"></div>'
 '<div style="padding:10px 16px;display:flex;justify-content:space-between;align-items:center">'
 '<span class="chip">확정됨</span>'
 f'<span style="font-size:14px;font-weight:700;color:var(--ink)">티켓 보기 {A}</span></div>'
 '</div>'+cta(mt=10)+FOLD+below())
# ⑥ 신문 1면
V[6]=(BAR+
 '<div style="border-bottom:2.5px solid var(--ink);margin:0 15px;padding:6px 0 8px;text-align:center">'
 '<div class="wm" style="font-size:27px">도그스하이</div></div>'
 '<div style="display:flex;justify-content:space-between;margin:0 15px;padding:5px 0;border-bottom:1px solid var(--hair)">'
 '<span class="mono-sm" style="color:var(--pdim)">2026.08.20 THU</span>'
 '<span class="mono-sm" style="color:var(--pdim)">반포 · NO.— · SINCE 2026.07</span></div>'
 '<div style="padding:14px 15px 0"><div class="mono-sm" style="color:var(--line)">오늘의 러닝</div>'
 '<div class="disp" style="font-size:31px;color:var(--ink);margin-top:6px">초코, 오후 3시 30분<br>한강으로 갑니다</div>'
 '<div style="font-size:14px;color:var(--pdim);margin-top:8px;border-top:1px solid var(--hair);padding-top:8px">'
 's4kim2025 러너 확정 · 5km · <span style="color:var(--ready);font-weight:700">확정됨</span></div></div>'
 +cta(mt=13)+FOLD+below())
# ⑦ 다이얼 홈
V[7]=(BAR+mast()+ST+
 '<div style="padding:14px 16px 4px"><div style="font-size:15px;color:var(--pdim)">오늘 얼마나 달릴까요</div>'
 '<div style="display:flex;align-items:flex-end;gap:3px;margin-top:10px;height:38px">'
 +''.join(f'<div style="flex:1;height:{h}px;background:{c}"></div>' for h,c in
   [(12,'#E6E3DD'),(12,'#E6E3DD'),(20,'#E6E3DD'),(12,'#E6E3DD'),(12,'#E6E3DD'),(20,'#E6E3DD'),(12,'#E6E3DD'),
    (38,'var(--line)'),(12,'#E6E3DD'),(12,'#E6E3DD'),(20,'#E6E3DD'),(12,'#E6E3DD'),(12,'#E6E3DD')])+
 '</div>'
 '<div style="display:flex;align-items:baseline;gap:8px;margin-top:8px">'
 '<span class="num" style="font-size:34px;color:var(--ink)">5.0</span><span style="font-size:15px;color:var(--pdim)">km · 약 35분 · 예상 12,000원</span></div>'
 '</div>'+cta('이 조건으로 러너 찾기',size=24,mt=12)+FOLD+below())
# ⑧ 아이 중심
V[8]=(BAR+mast()+
 '<div style="padding:16px 16px 12px;display:flex;align-items:center;gap:13px">'
 '<div style="width:56px;height:56px;flex:0 0 56px;border-radius:30px;background:#EFEAE2;border:1px solid #E0DAD0;'
 'display:flex;align-items:center;justify-content:center" class="disp"><span style="font-size:22px;color:var(--gink)">초</span></div>'
 '<div style="flex:1;min-width:0"><div class="disp" style="font-size:27px;color:var(--ink)">초코</div>'
 '<div style="font-size:14px;color:var(--pdim);margin-top:2px">이번 주 <span class="num" style="color:var(--ink);font-size:16px">6.2</span>km · 통산 <span class="num" style="color:var(--ink);font-size:16px">41</span>회</div></div>'
 '</div>'+ST+cta()+FOLD+below())
# ⑨ 타임라인
V[9]=(BAR+mast()+
 '<div style="padding:14px 16px 6px">'
 '<div style="display:flex;gap:13px"><div style="width:9px;flex:0 0 9px;display:flex;flex-direction:column;align-items:center;padding-top:6px">'
 '<span style="width:9px;height:9px;border-radius:5px;background:var(--ready)"></span>'
 '<span style="flex:1;width:1px;background:var(--hair);margin:4px 0"></span>'
 '<span style="width:9px;height:9px;border-radius:5px;border:1.5px solid var(--line)"></span></div>'
 '<div style="flex:1">'
 '<div style="padding-bottom:16px"><div class="mono-sm" style="color:var(--pdim)">오늘</div>'
 '<div style="font-size:19px;font-weight:700;color:var(--ink);margin-top:2px">오후 3:30 · 초코</div>'
 '<div style="font-size:13.5px;color:var(--pdim);margin-top:2px">s4kim2025 러너 · <span style="color:var(--ready);font-weight:700">확정됨</span></div></div>'
 '<div><div class="mono-sm" style="color:var(--pdim)">다음</div>'
 '<div class="disp" style="font-size:24px;color:var(--line);margin-top:3px">다음 하이 미리 예약</div>'
 '<div style="font-size:13.5px;color:var(--pdim);margin-top:2px">날짜만 고르면 돼요</div></div>'
 '</div></div></div>'+FOLD+below())
# ⑩ 카드 한 장
V[10]=(BAR+mast(serial=False)+
 '<div style="margin:12px 15px 0;background:var(--ncard);position:relative;padding:16px">'
 '<div class="foiledge" style="position:absolute;top:0;left:0;right:0;height:3px"></div>'
 '<div style="display:flex;justify-content:space-between"><span class="mono-sm" style="color:var(--gsheen)">NEXT RUN</span>'
 '<span class="mono-sm" style="color:var(--ndim)">SINCE 2026.07</span></div>'
 '<div class="disp" style="font-size:28px;color:#fff;margin-top:10px">8월 4일 오후 3:30</div>'
 '<div style="font-size:14px;color:var(--ndim);margin-top:5px">s4kim2025 러너 · 초코 · 5km</div>'
 '<div style="display:flex;justify-content:space-between;align-items:center;margin-top:14px;padding-top:12px;border-top:1px solid var(--nedge)">'
 '<span style="font-size:13px;color:#6FDBA0;font-weight:700">● 확정됨</span>'
 f'<span style="color:var(--gsheen);font-size:14px;font-weight:700">티켓 {A}</span></div></div>'
 +cta(mt=10)+FOLD+below())
# ⑪ 분할
V[11]=(BAR+
 '<div style="background:var(--night);padding:12px 16px 16px">'
 '<div style="display:flex;align-items:center;gap:9px"><span style="width:44px"></span><div style="flex:1;display:flex;justify-content:center;align-items:center;gap:8px">'
 '<img src="data:image/png;base64,__LOGO__" style="height:24px;filter:brightness(0) invert(1)">'
 '<span class="wm" style="color:#fff;font-size:18px">도그스하이</span></div>'
 '<span style="width:44px;text-align:right;color:#fff;font-size:19px">◔</span></div>'
 '<div style="display:flex;align-items:baseline;gap:16px;margin-top:14px">'
 '<div><span class="num" style="font-size:40px;color:#fff">41</span><span class="num" style="font-size:15px;color:var(--ndim)"> 회</span></div>'
 '<div><span class="num" style="font-size:40px;color:#fff">238</span><span class="num" style="font-size:15px;color:var(--ndim)"> km</span></div>'
 '<div style="flex:1;text-align:right"><span class="mono-sm" style="color:var(--gsheen)">SINCE 2026.07</span></div></div>'
 '<div style="margin-top:12px;padding-top:11px;border-top:1px solid var(--nedge);font-size:14px;color:#fff">'
 '오늘 오후 3:30 · s4kim2025 <span style="color:#6FDBA0;font-weight:700">확정됨</span></div>'
 '</div>'+cta(mt=0)+FOLD+below())
# ⑫ 여백
V[12]=(BAR+mast()+
 '<div style="padding:22px 16px 4px;font-size:15px;color:var(--pdim)">'
 '오늘 오후 3:30 · <span style="color:var(--ready);font-weight:700">확정됨</span></div>'
 f'<div style="padding:8px 16px 30px"><div class="disp" style="font-size:40px;color:var(--line)">다음 하이<br>미리 예약</div>'
 f'<div style="font-size:15px;color:var(--pdim);margin-top:12px">날짜만 고르면 돼요 {A}</div></div>'
 +FOLD+below())

M=[
 (1,'①','한 줄 한 결정','ONE ROW ONE CHOICE','카드도 상자도 없이 결정만 세로로 쌓는다. 각 줄이 곧 하나의 행동이고, 코랄은 그중 하나에만 붙는다.',
  '상태 줄 → 코랄 예약 줄 → 아래 탐색','<b>강점</b> 가장 적게 생각하게 한다 — 읽을 것이 라벨 3개','<b>약점</b> 평평해서 기억에 남는 물건이 없다'),
 (2,'②','상태 우선','STATE FIRST','앱을 여는 이유가 대개 "확인"이라면 상태가 히어로여야 한다. 예약은 두 번째로 내려간다.',
  '초록 점 → 38pt 상태 문장 → 아웃라인 예약','<b>강점</b> 진행 중일 때 가장 안심된다','<b>약점</b> 예약 없는 날엔 히어로가 빈다 (⑧ v2 상태 함수로 해결)'),
 (3,'③','기록 우선','RECORD FIRST','브랜드 논지(기록의 브랜드)를 접히는 선 위로. 숫자가 가장 크고, 상태와 행동이 뒤따른다.',
  '41·238·8 숫자 → 상태 줄 → 코랄 CTA','<b>강점</b> 매일 여는 이유가 "쌓인다"가 된다','<b>약점</b> P5 위반 — 기록 보러 온 게 아닌 날엔 결정이 한 칸 밀린다'),
 (4,'④','투 버튼','TWO BUTTONS','⑧ v2 순정. 접히는 선 위에 상태 한 줄과 큰 버튼 둘뿐. 가장 순수한 "생각하지 마".',
  '상태 줄 → 코랄 지금 찾기 → 잉크 예약','<b>강점</b> 결정까지 최단 · 이미 승인된 문법','<b>약점</b> 밋밋함의 원인이었던 바로 그 구성'),
 (5,'⑤','티켓','TICKET','다음 러닝이 뜯는 티켓이 된다. 포일 엣지·퍼포레이션·시리얼이 상태 줄을 대체한다.',
  '포일 엣지 → 29pt 날짜 → 확정 칩 → CTA','<b>강점</b> 세리머니가 홈으로 — 재질이 곧 프리미엄','<b>약점</b> 예약이 없으면 티켓 자리가 빈다'),
 (6,'⑥','신문 1면','FRONT PAGE','마스트헤드 + 날짜 라인 + 리드 기사. 워드마크가 디스플레이 예산을 쓰고 본문은 굵은 룰로 잡는다.',
  '네임플레이트 → 데이트라인 → 31pt 리드 → CTA','<b>강점</b> 매일 새 호가 나오는 느낌 — 재방문 동기','<b>약점</b> 벨/알림이 앉을 자리가 애매하다'),
 (7,'⑦','다이얼 홈','DIAL HOME','예약 화면의 km 다이얼을 홈으로. 화면 하나를 없애고 홈에서 바로 조건을 정한다.',
  '상태 줄 → 다이얼 → 5.0km/예상 → CTA','<b>강점</b> 탭 수가 실제로 줄어든다 (첫 원리적 개선)','<b>약점</b> 홈이 도구가 된다 · 예약 화면과 역할 중복'),
 (8,'⑧','아이 중심','DOG FIRST','초코가 앵커. 이름과 이번 주 거리가 먼저 오고 상태·행동이 뒤따른다.',
  '초코 27pt + 주간 숫자 → 상태 줄 → CTA','<b>강점</b> 감정적 진입 — 서비스가 아니라 우리 아이 이야기','<b>약점</b> 다견 가구에서 누구의 홈인지 흔들린다'),
 (9,'⑨','타임라인','TIMELINE','시간이 유일한 정렬축. 왼쪽 세로선 위에 오늘과 다음이 점으로 찍힌다.',
  '초록 점(오늘) → 코랄 점(다음) → 아래 탐색','<b>강점</b> "언제"가 한눈에 · 상태와 행동이 같은 문법','<b>약점</b> 예약이 여러 개면 선이 길어져 접히는 선을 넘는다'),
 (10,'⑩','카드 한 장','ONE ARTIFACT','나이트 카드 한 장이 상태를 통째로 들고 있다. 여권 세계가 홈에 한 장만 올라온다.',
  '포일 엣지 → 28pt 날짜 → 확정 → CTA','<b>강점</b> 밝은 홈에 어두운 물건 하나 — 대비가 곧 주목','<b>약점</b> 다크 아일랜드의 귀환 (은퇴시킨 이유가 있었다)'),
 (11,'⑪','분할','SPLIT','위 45%는 나이트(정체+기록+상태), 아래는 페이퍼(행동). 두 세계를 섞지 않고 나눈다.',
  '나이트 블록 전체 → 코랄 CTA → 탐색','<b>강점</b> 두 세계 법을 가장 정직하게 지킨다 (섞지 않고 분리)','<b>약점</b> 화면이 무거워지고 스크롤 위가 꽉 찬다'),
 (12,'⑫','여백','WHITESPACE','접히는 선 위에 요소 셋. 상태는 한 줄로 줄고 행동이 40pt로 화면을 채운다.',
  '작은 상태 한 줄 → 40pt 코랄 CTA → 끝','<b>강점</b> 의심의 여지가 없다 — 가장 강한 "하나의 결정"','<b>약점</b> 확인하러 온 사람에겐 정보가 부족하다'),
]
def spec(n,c,ko,en,d,eye,s1,s2):
    return (f'<div class="spec"><div class="sh"><span class="sn">{c}</span>'
      f'<span class="stt">{ko}<small>{en}</small></span></div>'
      f'<div class="sd">{d}</div><div class="eye">시선 {eye}</div>'
      f'<div class="ph">{V[n]}</div><div class="sf"><div>{s1}</div><div>{s2}</div></div></div>')
specs='\n'.join(spec(*m) for m in M)
html=open(F,encoding='utf-8').read().replace('__SPECIMENS__',specs)
tmp='/tmp/_logo_a.png'
subprocess.run(['sips','-Z','200',f'{ROOT}/app/assets/logo-alpha.png','--out',tmp],capture_output=True)
html=html.replace('__LOGO__',base64.b64encode(open(tmp,'rb').read()).decode())
text=re.sub(r'<[^>]+>',' ',html)
chars={c for c in set(text)|set('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ.·’—①②③④⑤⑥⑦⑧⑨⑩⑪⑫▮●') if ord(c)>31}
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
