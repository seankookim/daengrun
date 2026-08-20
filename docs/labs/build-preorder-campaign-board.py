#!/usr/bin/env python3
"""Builds docs/labs/preorder-campaign-board.html — the visual bench for the three
pre-order campaigns. References assets in place at /Users/sean/Desktop/post; open locally."""
import os, html
POST = "/Users/sean/Desktop/post"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "preorder-campaign-board.html")

_cache = {}
def a(n, w=360):
    """Inline the asset as a base64 JPEG so the board renders anywhere, with no
    dependency on file:// subresource loading or on the asset folder travelling with it."""
    key = (n, w)
    if key in _cache: return _cache[key]
    from PIL import Image
    import io, base64
    path = os.path.join(POST, n)
    if not os.path.exists(path):
        _cache[key] = ""; return ""
    im = Image.open(path).convert("RGB")
    im.thumbnail((w, w * 3))
    buf = io.BytesIO(); im.save(buf, "JPEG", quality=72, optimize=True)
    _cache[key] = "data:image/jpeg;base64," + base64.b64encode(buf.getvalue()).decode()
    return _cache[key]

GRID = [
 ("1", "REMOVE NIKE.png", "매니페스토 · 다크 앵커", "⚠ 스우시 제거 후"),
 ("2", "exec-2027525e-15b1-4dc3-9d62-cf497fd44342.png", "CHASE THAT HIGH.", ""),
 ("3", "exec-15c57834-8c8d-49a5-bc27-e5884b5bfbe0.png", "한 페이스 두 심장", ""),
 ("4", "exec-4ae213f9-1503-4645-8c35-9d8c0bdac5cc.png", "BORN TO RUN", ""),
 ("5", "film grain 2.png", "TWO HEARTS. ONE PACE. — 이 캠페인의 단 하나의 이미지", ""),
 ("6", "exec-f8ab15af-ecdc-4c76-9592-bf3eec5f2deb.png", "오래 달릴 사이.", ""),
 ("7", "exec-729b5c4e-49e6-4cae-98e5-33da44bb3c17.png", "A TIRED DOG IS A HAPPY DOG.", ""),
 ("8", "exec-6cda8872-500b-4dfb-acc9-014c4e0bb4dd.png", "DOES YOUR DOG RUN?", ""),
 ("9", "exec-cb63cecf-8a86-4794-9ad3-5a35846c1431.png", "지금이야", ""),
]

TS = [
 ("TS-1", "DOES YOUR DOG RUN? · 보호자 · 7컷", [
   ("exec-6cda8872-500b-4dfb-acc9-014c4e0bb4dd.png", "우리 개는 산책으론 안 빠져요"),
   ("exec-729b5c4e-49e6-4cae-98e5-33da44bb3c17.png", "끄는 개는 나쁜 개가 아닙니다"),
   ("exec-50ed71e7-86a2-49a9-8bf8-d63a00d4619a.png", "남은 에너지입니다"),
   ("exec-15c57834-8c8d-49a5-bc27-e5884b5bfbe0.png", "운동량으로만 빠지는 당김이 있습니다"),
   ("exec-31d0246c-ca57-4fe5-9f6f-d346cce84b79.png", "그걸 저희가 맡습니다"),
   ("exec-f4103119-dd7f-41cb-be78-3ba0c5c28c31.png", "인증 러너가 뛰고, GPS로 남습니다"),
   (None, "타입 카드 — 창립멤버 사전등록"),
 ]),
 ("TS-2", "밤 11시에 하는 짓 · 보호자 · 8컷", [
   (None, "밤 11시에 거실을 도는 개"),
   ("수건뺴고니온보이게.png", "아침엔 문 앞에 두고 나갑니다"),
   ("exec-2646005c-9e9b-44e6-a512-ab3d84b16071.png", "못 뛰어준 날이 쌓입니다"),
   ("dumb/ChatGPT Image Aug 4, 2026, 01_08_45 PM (1).png", "— 오늘은 아니고요 (전환)"),
   ("dumb/ChatGPT Image Aug 4, 2026, 01_12_24 PM (3).png", "인증 러너가 대신 뜁니다"),
   ("exec-9db065c2-92ec-4264-9239-a035f055f886.png", "8:08/km · 4.6km — 기록이 남습니다"),
   ("exec-f8ab15af-ecdc-4c76-9592-bf3eec5f2deb.png", "지친 개, 조용한 저녁"),
   (None, "타입 카드 — 창립멤버 사전등록"),
 ]),
 ("TS-3", "뛰던 길에서, 벌자 · 러너 · 8컷 (우선순위)", [
   ("exec-942fc070-709f-4a5b-8159-3bb0a1cb69ed.png", "어차피 뛸 5km입니다"),
   ("exec-f2abbd45-f4d9-4395-9292-d440b7a67708.png", "페이가 붙을 뿐이고요"),
   (None, "표 카드 — 5km ₩16,683 · 7km ₩20,703"),
   (None, "표 카드 — 시간당은 직접 계산해보세요"),
   (None, "표 카드 — 보장은 안 합니다"),
   ("exec-4ae213f9-1503-4645-8c35-9d8c0bdac5cc.png", "초기 러너일수록 배정이 먼저"),
   ("exec-787fe7f3-1555-406d-8534-83af7294dc62.png", "페이스 테스트 · 핸들링 · 승인"),
   (None, "타입 카드 — 1기 인증 러너 모집"),
 ]),
 ("TS-4", "붙는 기준을 먼저 공개합니다 · 러너 · 6컷 · 타입 전용", [
   (None, "러너 모집 공고는 보통 붙은 사람부터 보여줍니다"),
   (None, "순서를 바꿉니다"), (None, "① 5km 페이스 테스트"),
   (None, "② 반려견 핸들링 온보딩"), (None, "③ 승인 · ④ 배정"),
   (None, "넷 중 하나라도 안 되면 배정하지 않습니다"),
 ]),
 ("TS-5", "우리 개 에너지 테스트 · 보호자 · 6컷 · 참여형", [
   ("exec-cb63cecf-8a86-4794-9ad3-5a35846c1431.png", "우리 개 에너지 테스트 — 몇 개?"),
   (None, "① 하루 운동 1시간 미만"), (None, "② 밤 11시에 거실을 돈다"),
   (None, "③ 산책 다녀와도 안 자"), (None, "④ \"산책으론 안 빠져요\"를 말해본 적 있다"),
   ("exec-b10160bc-e30b-419a-91b6-f9472360978b.png", "3개 이상이면 댓글에 견종"),
 ]),
 ("TS-6", "사전주문 · 양 방언 · 5컷 · ⚠ 심사 승인 전 제작 금지", [
   ("REMOVE NIKE.png", "사전주문 시작 (스우시 제거 후)"),
   ("film grain 2.png", "출시일에 자동으로 설치됩니다"),
   ("exec-6c5f7ae1-b1b4-4470-8867-84491236c736.png", "인증 러너가 뛰고, 지도에 남습니다"),
   (None, "바디캠은 아직 준비 중입니다"),
   (None, "한강 인근부터. 순서대로 엽니다."),
 ]),
]

SWOOSH = ["REMOVE NIKE.png", "도그스로바꿔.png", "dumb/remove nike logo.png",
          "dumb/ChatGPT Image Aug 4, 2026, 01_18_34 PM.png",
          "dumb/ChatGPT Image Aug 4, 2026, 02_18_54 PM.png",
          "dumb/ChatGPT Image Aug 4, 2026, 03_23_04 PM (4) copy.png",
          "dumb/ChatGPT Image Aug 4, 2026, 03_23_05 PM (6) copy 3.png",
          "dumb/ChatGPT Image Aug 4, 2026, 03_23_05 PM (6) copy 4.png",
          "dumb/ChatGPT Image Aug 4, 2026, 03_23_05 PM (7).png",
          "dumb/ChatGPT Image Aug 4, 2026, 03_23_05 PM (8) copy.png",
          "dumb/ChatGPT Image Aug 4, 2026, 03_23_05 PM (8).png"]

def card(fn, cap, warn=""):
    if fn is None:
        body = f'<div class="mk">TYPE<br>CARD</div>'
    else:
        miss = "" if os.path.exists(os.path.join(POST, fn)) else " missing"
        body = f'<img class="ph{miss}" src="{a(fn, 210)}" alt="">'
    w = f'<div class="warn">{html.escape(warn)}</div>' if warn else ""
    return f'<figure>{body}{w}<figcaption>{html.escape(cap)}</figcaption></figure>'

parts = []
parts.append("""<!doctype html><meta charset="utf-8"><title>도그스하이 — 사전예약 캠페인 벤치</title>
<style>
:root{--ink:#171A17;--paper:#fff;--clay:#EFF1EC;--line:#D8DAD2;--red:#FF5C3D;--forest:#0F1D13;--violet:#7B6CDF}
*{box-sizing:border-box}body{margin:0;background:var(--clay);color:var(--ink);
font:15px/1.55 -apple-system,BlinkMacSystemFont,"Apple SD Gothic Neo",sans-serif}
header{background:var(--forest);color:#fff;padding:40px 32px}
header h1{margin:0;font-size:30px;letter-spacing:-.5px}
header p{margin:8px 0 0;color:#9fb0a4;max-width:70ch}
main{padding:32px;max-width:1400px;margin:0 auto}
section{background:var(--paper);border:1px solid var(--line);border-radius:14px;padding:24px;margin:0 0 24px}
h2{margin:0 0 4px;font-size:20px}h2 .n{color:var(--red)}
.sub{margin:0 0 18px;color:#586055;font-size:14px}
.grid9{display:grid;grid-template-columns:repeat(3,1fr);gap:6px;max-width:660px}
.grid9 figure{margin:0;position:relative}
.grid9 img{width:100%;aspect-ratio:1/1;object-fit:cover;display:block;border-radius:2px}
.grid9 figcaption{font-size:11px;color:#586055;padding:4px 2px;line-height:1.35}
.grid9 .num{position:absolute;top:6px;left:6px;background:rgba(15,29,19,.82);color:#fff;
font-size:11px;padding:2px 6px;border-radius:4px}
.strip{display:flex;gap:10px;overflow-x:auto;padding-bottom:8px}
.strip figure{margin:0;flex:0 0 132px}
.strip .ph,.strip .mk{width:132px;height:235px;object-fit:cover;border-radius:6px;display:block}
.mk{background:var(--clay);border:1px dashed var(--line);display:flex;align-items:center;
justify-content:center;font-size:11px;color:#586055;text-align:center;letter-spacing:1px}
.strip figcaption{font-size:11px;color:#3a403a;padding-top:6px;line-height:1.35}
.warn{font-size:10px;color:#fff;background:var(--red);padding:2px 5px;border-radius:3px;
display:inline-block;margin-top:4px}
.missing{outline:3px solid var(--red)}
.flags{display:grid;grid-template-columns:repeat(auto-fill,minmax(190px,1fr));gap:6px;
font-size:12px;color:#586055}
.flags code{background:var(--clay);padding:2px 5px;border-radius:3px;font-size:11px}
.note{border-left:3px solid var(--violet);padding:2px 0 2px 14px;margin:16px 0;color:#3a403a;font-size:14px}
.q{border-left:3px solid var(--red);padding:2px 0 2px 14px;margin:16px 0;font-size:14px}
</style>
<header>
<h1>도그스하이 — 사전예약 캠페인 벤치</h1>
<p>보고 고르는 판. 실제 파일을 그대로 참조합니다 (<code>~/Desktop/post</code>). 이미지가 빨간 테두리로
보이면 그 파일이 그 자리에 없다는 뜻입니다. 문서: <code>docs/campaigns/</code> 3종.</p>
</header><main>""")

parts.append('<section><h2><span class="n">A.</span> 인스타그램 런치 9컷</h2>'
 '<p class="sub">발행 순서 9 → 2, 1번은 리빌일에. 8컷 상태에서는 컴포지션이 한 칸씩 밀려 있고, '
 '1번이 올라가는 순간 제자리로 스냅됩니다.</p><div class="grid9">')
for n, fn, cap, warn in GRID:
    miss = "" if os.path.exists(os.path.join(POST, fn)) else " missing"
    w = f'<div class="warn">{html.escape(warn)}</div>' if warn else ""
    parts.append(f'<figure><span class="num">{n}</span>'
                 f'<img class="{miss.strip()}" src="{a(fn)}" alt="">{w}'
                 f'<figcaption>{html.escape(cap)}</figcaption></figure>')
parts.append('</div><div class="note">다크 앵커는 1번 하나. 2행이 블루/더스크로 끊어 주지 않으면 '
 '아홉 칸이 한 장의 포스터로 뭉갭니다. 아홉 컷 전부 AI 생성이므로 프레임 안에 '
 '<code>콘셉트 이미지 · 서비스 준비 중</code> 밴드가 들어갑니다 — 캡션이 <code>⌁⌁</code> 한 줄뿐인 '
 '티저 주간에는 이게 유일한 고지입니다.</div></section>')

for tid, title, slides in TS:
    parts.append(f'<section><h2><span class="n">{tid}</span> {html.escape(title)}</h2>'
                 f'<p class="sub">1080×1920로 상하 패딩(#0F1D13). 좌우 크롭 금지 — 헤드라인 타입이 잘립니다. '
                 f'하단 밴드에 워드마크와 고지.</p><div class="strip">')
    for fn, cap in slides:
        warn = "⚠ 스우시 제거 필요" if fn in SWOOSH else ""
        parts.append(card(fn, cap, warn))
    parts.append('</div></section>')

parts.append('<section><h2><span class="n">B.</span> 발행 전 하드 게이트</h2>'
 '<p class="sub">아래 파일에서 나이키 스우시를 눈으로 확인했습니다. 제거 전에는 어떤 채널에도 '
 '올라갈 수 없습니다. <code>dumb/</code>는 기본적으로 리젝트 통으로 취급하세요 — 이름이 거의 같은 '
 '리터치 전/후 파일이 섞여 있어서, 기억이 아니라 지금 올릴 그 파일을 확인해야 합니다.</p>'
 '<div class="flags">')
for s in SWOOSH:
    parts.append(f'<div><code>{html.escape(s)}</code></div>')
parts.append('</div><div class="q"><b>Sean 결정 대기</b><br>'
 'Q1. 반복 시그니처: 문서의 volt 펄스 레일인가, 실제 자산의 바이올렛 GPS 트레이스인가.<br>'
 'Q2. 영문 라인 세트(CHASE THAT HIGH / TWO HEARTS. ONE PACE. / A TIRED DOG IS A HAPPY DOG.)를 '
 '정본으로 채택할 것인가, 이번 시즌만 쓸 것인가.<br>'
 'Q3. 번들 ID <code>com.seankookim.daengrun</code> — 첫 업로드 후에는 영구 고정. 지금 바꾸는가.<br>'
 'Q4. 사전주문 출시일은 인증 러너가 실재한 다음에만 고를 수 있습니다. 순서 확인.</div></section>')
parts.append('</main>')
open(OUT, "w").write("\n".join(parts))
print("wrote", OUT)
