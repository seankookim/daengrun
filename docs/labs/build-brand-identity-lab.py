#!/usr/bin/env python3
import base64, io, re, subprocess, os, sys
from fontTools import subset
from fontTools.ttLib import TTFont

ROOT="/Users/sean/dev/daengrun"
F=f"{ROOT}/docs/labs/brand-identity-lab.html"

BELL=('<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round">'
 '<path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.7 21a2 2 0 0 1-3.4 0"/></svg>')
CH=('<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" '
 'stroke-linejoin="round"><path d="M9 18l6-6-6-6"/></svg>')

def bar(): return '<div class="bar"><span>11:03</span><span class="isl"></span><span style="font-size:10px">▮▮▮</span></div>'
def mast():
    return (f'<div class="mast"><div class="sp"></div><div class="lg">'
     f'<img src="data:image/png;base64,__LOGO__" style="height:28px">'
     f'<span class="wm">도그스하이</span></div><div class="bell">{BELL}<i></i></div></div>')
def st():
    return ('<div class="st"><span class="when"><span class="num">8월 4일</span> (화) <span class="num">오후 3:30</span></span>'
     '<span class="who">s4kim2025</span><span class="chip">확정됨</span></div>')
def cta(label='다음 하이 미리 예약',size=26):
    return f'<div class="cta"><b style="font-size:{size}px">{label}</b>{CH}</div>'

S={}
# Ⅰ 절제 — Plex body + serial row + coral hairline returns
S[1]=(bar()+mast()
 +'<div style="height:2px;margin:6px 0 0" class="foiledge" ></div>'.replace('foiledge','')  # placeholder no-op
 +'<div style="height:0;border-top:1px solid var(--p-line);margin:5px 15px 0"></div>'
 +'<div class="serialrow"><span class="sr">NO. 0001</span><span class="dt">MEMBER SINCE 2026.07</span></div>'
 +st()+cta()
 +'<div class="kickrow">동네</div>'
 +'<div style="margin:0 15px;padding:13px 0;border-top:1px solid #EEE;font-size:15px;color:var(--p-ink);font-weight:700">반포동 하이클럽<div style="font-size:13.5px;color:var(--p-dim);font-weight:400;margin-top:2px">호스트 · 멤버 1명</div></div>')
# Ⅱ 중간 — + ⑦ gold club + 기록 chunk with Oswald numerals
S[2]=(bar()+mast()
 +'<div style="height:0;border-top:1px solid var(--p-line);margin:5px 15px 0"></div>'
 +'<div class="serialrow"><span class="sr">NO. 0001</span><span class="dt">MEMBER SINCE 2026.07</span></div>'
 +st()+cta()
 +'<div class="kickrow">기록</div>'
 +'<div style="display:flex;margin:0 15px;border-top:2px solid var(--p-ink)">'
 +'<div style="flex:1;padding:10px 0 4px;border-right:1px solid #EEE"><div class="mono-sm" style="color:#999">이번 주</div><div class="num" style="font-size:26px;color:var(--p-ink)">6.2<small style="font-size:14px;color:var(--p-dim)">km</small></div></div>'
 +'<div style="flex:1;padding:10px 0 4px 14px;border-right:1px solid #EEE"><div class="mono-sm" style="color:#999">통산</div><div class="num" style="font-size:26px;color:var(--p-ink)">41<small style="font-size:14px;color:var(--p-dim)">회</small></div></div>'
 +'<div style="flex:1;padding:10px 0 4px 14px"><div class="mono-sm" style="color:#999">도장</div><div class="num" style="font-size:26px;color:var(--p-ink)">8</div></div>'
 +'</div>'
 +'<div class="kickrow">동네</div>'
 +'<div class="club7"><div class="nm">반포동 하이클럽</div><div class="mt">호스트 · 멤버 1명</div></div>')
# Ⅲ 전면 — night plate hero + foil + MRZ
S[3]=(bar()+mast()
 +'<div style="height:0;border-top:1px solid var(--p-line);margin:5px 15px 0"></div>'
 +st()
 +'<div style="margin:7px 15px 0;background:var(--n-bg);position:relative;padding:16px 16px 12px">'
 +'<div class="foiledge" style="position:absolute;top:0;left:0;right:0;height:3px"></div>'
 +'<div style="display:flex;justify-content:space-between;align-items:baseline">'
 +'<span class="mono-sm" style="color:var(--l-goldSheen)">기록면 · RECORD</span>'
 +'<span class="mono-sm" style="color:var(--n-dim)">NO. 0001</span></div>'
 +'<div class="num" style="font-size:44px;color:#fff;margin-top:8px">41<small style="font-size:17px;color:var(--n-dim)"> 회</small>'
 +'<span class="num" style="font-size:44px;color:#fff;margin-left:18px">238<small style="font-size:17px;color:var(--n-dim)"> km</small></span></div>'
 +'<div style="font-family:ui-monospace,monospace;font-size:9.5px;letter-spacing:.09em;color:#4E4680;margin-top:10px;line-height:1.5">P&lt;KOR&lt;DOGSHIGH&lt;&lt;CHOCO&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;<br>0001&lt;&lt;2026.07&lt;&lt;BANPO&lt;&lt;&lt;&lt;41RUNS&lt;238KM&lt;&lt;&lt;&lt;</div>'
 +'</div>'
 +cta()
 +'<div class="kickrow">동네</div>'
 +'<div class="club7" style="margin-top:2px"><div class="nm">반포동 하이클럽</div><div class="mt">호스트 · 멤버 1명</div></div>')

CERT=('<div class="cert"><div class="edge foiledge"></div><div class="cert-in">'
 '<div class="hd"><span class="mono-sm" style="color:var(--l-goldSheen)">도그스하이 · 러닝 기록증</span>'
 '<span class="mono-sm" style="color:var(--n-dim)">NO. 0041</span></div>'
 '<div class="nm">초코의 마흔한 번째 러닝</div>'
 '<div class="sub">2026년 8월 4일 (화) · 반포 한강공원 · s4kim2025 러너</div>'
 '<div class="bignum">6.2<small> km</small></div>'
 '<div class="row3">'
 '<div><div class="lb">시간</div><div class="vl">42:07</div></div>'
 '<div style="padding-left:14px"><div class="lb">페이스</div><div class="vl">6\'47"</div></div>'
 '<div style="padding-left:14px"><div class="lb">통산</div><div class="vl">238km</div></div>'
 '</div>'
 '<div class="foot"><div class="mrz">P&lt;KOR&lt;DOGSHIGH&lt;&lt;CHOCO&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;<br>0041&lt;&lt;20260804&lt;&lt;62KM&lt;&lt;BANPO&lt;&lt;&lt;&lt;&lt;</div>'
 '<div class="stamp"><b>하이</b></div></div>'
 '</div></div>')

def spec(n,circ,title,en,desc,body,feet,cert=False):
    fh=''.join(f'<div>{x}</div>' for x in feet)
    frame = body if cert else f'<div class="ph">{body}</div>'
    return (f'<div class="spec"><div class="spec-h"><span class="spec-n">{circ}</span>'
     f'<span class="spec-t">{title}<small>{en}</small></span></div>'
     f'<div class="spec-d">{desc}</div>{frame}<div class="spec-f">{fh}</div></div>')

specs=[
 spec(1,'Ⅰ','절제','RESTRAINED','오늘 커밋 가능한 최소: Plex 본문 · 코랄 헤어라인 귀환 · 일련번호+가입일 한 줄. 흰 세계 유지, 재질은 활자와 숫자뿐.',S[1],
  ['<b>일련번호</b> Tracksmith의 keepsake number — 낮은 번호가 공짜 연공서열이 된다','<b>비용</b> S — 전부 기존 토큰']),
 spec(2,'Ⅱ','중간','BALANCED · 권고',' Ⅰ + 기록 청크(Oswald 숫자가 홈에 데뷔) + ⑦ 각인 클럽. 숫자가 브랜드 자산이라는 논지가 매일 화면에 앉는다.',S[2],
  ['<b>기록 청크</b> "오늘 6.2km · 통산 41회" — 격려가 아니라 기록의 문장','<b>비용</b> M — 신규 모듈 하나 + ⑦ 이식']),
 spec(3,'Ⅲ','전면','FULL','기록면이 홈에 올라온다: 나이트 플레이트 + 포일 엣지 + MRZ. 여권이 가장자리에서 중앙으로.',S[3],
  ['<b>대가</b> 홈의 밝은 성격 일부 포기 — 다크 아일랜드의 귀환','<b>비용</b> L — ⑧ v2 구조 재협상']),
 spec(4,'④','기록증','THE CERTIFICATE','논지의 증거물 — 수료증 갭을 채우는 물건. 완주마다 발행, 공유 가능, 런클립이 증명한 "증명의 타이포에 돈을 낸다"의 우리 답.',CERT,
  ['<b>스키마</b> 마라톤 기록증 문법 차용: 이름·번호·날짜·코스·기록·통산','<b>자리</b> 리포트의 공유 카드 옆 — 서버 변경 0'],cert=True),
]
sp='\n'.join(specs)
html=open(F,encoding='utf-8').read().replace('__SPECIMENS__',sp)

tmp='/tmp/_logo_b.png'
subprocess.run(['sips','-Z','200',f'{ROOT}/app/assets/logo-alpha.png','--out',tmp],capture_output=True)
html=html.replace('__LOGO__',base64.b64encode(open(tmp,'rb').read()).decode())

text=re.sub(r'<[^>]+>',' ',html)
chars={c for c in set(text)|set('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ.·\'"<>:’—×①②③④ⅠⅡⅢ▮') if ord(c)>31}
FONTS={'__FONT_BHS__':'black-han-sans/400Regular/BlackHanSans_400Regular.ttf',
 '__FONT_OSW__':'oswald/600SemiBold/Oswald_600SemiBold.ttf',
 '__FONT_BODY__':'ibm-plex-sans-kr/400Regular/IBMPlexSansKR_400Regular.ttf',
 '__FONT_BODYB__':'ibm-plex-sans-kr/700Bold/IBMPlexSansKR_700Bold.ttf'}
for tok,rel in FONTS.items():
    p=f'{ROOT}/app/node_modules/@expo-google-fonts/{rel}'
    f=TTFont(p); o=subset.Options(); o.layout_features=['*']; o.notdef_outline=True; o.desubroutinize=True
    s=subset.Subsetter(options=o); s.populate(text=''.join(sorted(chars))); s.subset(f)
    b=io.BytesIO(); f.flavor='woff2'; f.save(b)
    print(tok,f'{len(b.getvalue())//1024}KB')
    html=html.replace(tok,base64.b64encode(b.getvalue()).decode())
open(F,'w',encoding='utf-8').write(html)
print('WROTE',F,f'{len(html)//1024}KB')
