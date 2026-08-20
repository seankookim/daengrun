#!/usr/bin/env python3
"""Self-contained index of the rendered posts. Images are inlined so the page renders anywhere."""
import os, io, base64, html
from PIL import Image
HERE=os.path.dirname(os.path.abspath(__file__)); P=os.path.join(HERE,"posts")
OUT=os.path.join(HERE,"preorder-posts.html")
def uri(path,w):
    im=Image.open(path).convert("RGB"); im.thumbnail((w,w*3))
    b=io.BytesIO(); im.save(b,"JPEG",quality=72,optimize=True)
    return "data:image/jpeg;base64,"+base64.b64encode(b.getvalue()).decode()
TS_T={"TS-1":"DOES YOUR DOG RUN? · 보호자 · 1순위",
      "TS-2":"밤 11시에 하는 짓 · 보호자 · 저장률",
      "TS-3":"뛰던 길에서, 벌자 · 러너 · 2순위 (공급 병목)",
      "TS-4":"붙는 기준을 먼저 공개합니다 · 러너 · 타입 전용",
      "TS-5":"우리 개 에너지 테스트 · 보호자 · 참여형",
      "TS-6":"사전주문 · ⚠ 심사 승인 전 발행 금지"}
p=["""<!doctype html><meta charset="utf-8"><title>도그스하이 — 렌더된 포스트</title><style>
:root{--ink:#171A17;--paper:#fff;--clay:#EFF1EC;--line:#D8DAD2;--red:#FF5C3D;--forest:#0F1D13}
*{box-sizing:border-box}body{margin:0;background:var(--clay);color:var(--ink);
font:15px/1.55 -apple-system,BlinkMacSystemFont,"Apple SD Gothic Neo",sans-serif}
header{background:var(--forest);color:#fff;padding:38px 32px}h1{margin:0;font-size:28px}
header p{margin:8px 0 0;color:#9fb0a4;max-width:74ch}
main{padding:28px;max-width:1360px;margin:0 auto}
section{background:var(--paper);border:1px solid var(--line);border-radius:14px;padding:22px;margin:0 0 22px}
h2{margin:0 0 3px;font-size:19px}h2 .n{color:var(--red)}.sub{margin:0 0 16px;color:#586055;font-size:13.5px}
.two{display:flex;gap:26px;flex-wrap:wrap}.two>div{flex:1;min-width:300px}
.two img{width:100%;border:1px solid var(--line);border-radius:6px;display:block}
.two h3{font-size:13px;margin:0 0 8px;color:#586055;font-weight:600;letter-spacing:.3px}
.tiles{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:10px}
.tiles figure{margin:0}.tiles img{width:100%;border-radius:5px;display:block}
.tiles figcaption{font-size:11px;color:#586055;padding-top:4px}
.strip{display:flex;gap:9px;overflow-x:auto;padding-bottom:6px}
.strip figure{margin:0;flex:0 0 118px}.strip img{width:118px;border-radius:5px;display:block}
.strip figcaption{font-size:10.5px;color:#586055;padding-top:4px}
.warn{border-left:3px solid var(--red);padding:2px 0 2px 13px;margin:14px 0;font-size:13.5px}
</style><header><h1>도그스하이 — 렌더된 포스트</h1>
<p>실제 업로드 파일입니다. 인스타 9컷(1080×1350)과 틱톡 6편 40컷(1080×1920).
파일: <code>docs/labs/posts/</code> · 캡션과 발행 순서: 같은 폴더의 <code>README.md</code>.</p></header><main>"""]

p.append('<section><h2><span class="n">A.</span> 프로필 그리드 — 두 비율 다 확인</h2>'
 '<p class="sub">포스터 전체가 4:5 프레임의 가운데 정사각형 안에 들어가 있습니다. 1:1로 잘려도 헤드라인이 '
 '살아 있으면 어떤 비율에서도 삽니다. 첫 렌더는 4·6·8번의 타입을 잘라먹었고, 그래서 이렇게 바꿨습니다.</p>'
 '<div class="two">'
 f'<div><h3>1:1 (최악의 경우)</h3><img src="{uri(os.path.join(P,"ig","GRID-1x1.jpg"),620)}"></div>'
 f'<div><h3>3:4</h3><img src="{uri(os.path.join(P,"ig","GRID-3x4.jpg"),620)}"></div>'
 '</div></section>')

p.append('<section><h2><span class="n">B.</span> 인스타 9컷 · 발행 순서 09 → 02, 01은 리빌일</h2>'
 '<p class="sub">1번은 잘라낸 게 아니라 만든 겁니다 — 그래서 <code>REMOVE NIKE.png</code>의 스우시 문제를 '
 '통째로 피해 갑니다. 나머지 8컷은 전부 AI라 프레임 안에 고지 밴드가 들어 있습니다.</p><div class="tiles">')
for i in range(1,10):
    f=os.path.join(P,"ig",f"{i:02d}.jpg")
    p.append(f'<figure><img src="{uri(f,300)}"><figcaption>{i:02d}.jpg</figcaption></figure>')
p.append('</div></section>')

for tid,title in TS_T.items():
    d=os.path.join(P,"tiktok",tid); files=sorted(os.listdir(d))
    p.append(f'<section><h2><span class="n">{tid}</span> {html.escape(title)}</h2>'
             f'<p class="sub">{len(files)}컷 · 1080×1920 · 하단 밴드에 워드마크와 고지</p><div class="strip">')
    for fn in files:
        p.append(f'<figure><img src="{uri(os.path.join(d,fn),236)}"><figcaption>{fn}</figcaption></figure>')
    p.append('</div></section>')

p.append('<section><h2><span class="n">C.</span> 올리기 전에</h2><div class="warn">'
 '<b>서체는 임시입니다.</b> 이 기계에 Black Han Sans가 없어서 한글 디스플레이는 Apple SD Gothic Neo Bold, '
 '영문은 Arial Black으로 대체했습니다. 설치하고 <code>build-posts.py</code>를 다시 돌리면 그대로 교체됩니다. '
 '포스터에 이미 박혀 있는 헤드라인은 영향 없습니다 — 제가 새로 앉힌 타입(1번 타일·타입 카드·슬라이드 문구·고지)만 해당됩니다.'
 '</div><div class="warn"><b>앱스토어 스크린샷은 여기 없습니다.</b> 스토어 스크린샷은 실제 앱에서 찍어야 하고'
 '(AI 금지 표면), 빌드가 한 번도 나온 적이 없습니다. 지어내지 않았습니다.</div>'
 '<div class="warn"><b>TS-6은 홀드.</b> 심사 승인 + 출시일 확정 전에는 “사전주문”과 “출시일”이라는 단어가 '
 '어느 채널에도 나가지 않습니다.</div></section></main>')
open(OUT,"w").write("\n".join(p)); print("wrote",OUT, os.path.getsize(OUT)//1024,"KB")
