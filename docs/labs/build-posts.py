#!/usr/bin/env python3
"""Renders publish-ready post files for the three pre-order campaigns.

Outputs to docs/labs/posts/:
  mark/            logo mark extracted to transparent PNG (white + red)
  ig/              9 feed tiles, 1080x1350, in-frame AI disclosure
  ig/GRID.jpg      what the profile grid will actually look like (centre-square crops)
  tiktok/TS-n/     1080x1920 slides, forest bands, wordmark + disclosure
  CONTACT-*.jpg    verification sheets

TYPE STAND-IN: Black Han Sans is not installed on this machine. Korean display type falls back to
Apple SD Gothic Neo Bold and Latin display to Arial Black. Install Black Han Sans and re-run to
get the real lockup — nothing else in this script changes.
"""
import os, io
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageEnhance

POST = "/Users/sean/Desktop/post"
HERE = os.path.dirname(os.path.abspath(__file__))
OUT  = os.path.join(HERE, "posts")

FOREST="#0F1D13"; PAPER="#FFFFFF"; CLAY="#EFF1EC"; INK="#171A17"
RED="#FF5C3D"; VIOLET="#7B6CDF"; LINE="#D8DAD2"; DIM="#586055"; BAND="#D8DAD2"

KR = "/System/Library/Fonts/AppleSDGothicNeo.ttc"
LAT= "/System/Library/Fonts/Supplemental/Arial Black.ttf"
def kr(sz, w="Bold"):
    idx = {"Regular":0,"Medium":2,"SemiBold":4,"Bold":6}[w]
    return ImageFont.truetype(KR, sz, index=idx)
def lat(sz): return ImageFont.truetype(LAT, sz)

DISCLOSURE = "콘셉트 이미지 · 서비스 준비 중"

def ensure(*p):
    d = os.path.join(OUT, *p); os.makedirs(d, exist_ok=True); return d

# ---------------------------------------------------------------- logo mark
def extract_mark(src, name):
    """Black-ground glyph plate -> transparent PNG. Alpha = per-pixel max channel,
    which is exact here because the plate ground is pure black."""
    im = Image.open(os.path.join(POST, src)).convert("RGB")
    r,g,b = im.split()
    alpha = Image.new("L", im.size)
    px = alpha.load(); rp,gp,bp = r.load(), g.load(), b.load()
    for y in range(im.height):
        for x in range(im.width):
            px[x,y] = max(rp[x,y], gp[x,y], bp[x,y])
    out = im.convert("RGBA"); out.putalpha(alpha)
    out = out.crop(out.getbbox())
    p = os.path.join(ensure("mark"), name); out.save(p)
    return out

def paste_mark(canvas, mark, x, y, h, anchor="lm"):
    m = mark.copy(); w = int(m.width * h / m.height); m = m.resize((w,h), Image.LANCZOS)
    if anchor.endswith("m"): y -= h//2
    if anchor.startswith("r"): x -= w
    canvas.paste(m, (int(x), int(y)), m); return w

# ---------------------------------------------------------------- text
def fit_font(text, maxw, mk, start, floor=14):
    sz = start
    while sz > floor:
        f = mk(sz)
        if f.getbbox(text) and f.getbbox(text)[2] - f.getbbox(text)[0] <= maxw: return f
        sz -= 2
    return mk(floor)

def wrap(text, font, maxw, draw):
    words = text.split(" "); lines=[]; cur=""
    for w in words:
        t = (cur+" "+w).strip()
        if draw.textlength(t, font=font) <= maxw: cur = t
        else:
            if cur: lines.append(cur)
            cur = w
    if cur: lines.append(cur)
    return lines

def block(draw, x, y, text, font, fill, maxw, lh=1.28, anchor="la"):
    lines = wrap(text, font, maxw, draw)
    step = int(font.size*lh)
    for i,l in enumerate(lines):
        draw.text((x, y+i*step), l, font=font, fill=fill, anchor=anchor)
    return y + len(lines)*step

# ---------------------------------------------------------------- frames
def blur_bleed(asset, W, H, safe=None):
    """Contain the asset over a blurred cover of itself — zero content loss.

    `safe` is the centred box the whole poster must fit inside. It exists because Instagram's
    profile grid crops a 4:5 post, and a cut headline is what the first render actually produced
    (tiles 4, 6 and 8 lost their type). Fitting the poster inside the centred SQUARE means the
    composition survives a 1:1 grid, a 3:4 grid, and the full-size feed view alike — the launch
    mechanic is nine tiles reading as one picture, so a crop that eats type is not a style choice."""
    if safe is None: safe = (W, min(W, H))
    bg = asset.copy()
    s = max(W/bg.width, H/bg.height)
    bg = bg.resize((int(bg.width*s)+1, int(bg.height*s)+1), Image.LANCZOS)
    bg = bg.crop(((bg.width-W)//2, (bg.height-H)//2, (bg.width-W)//2+W, (bg.height-H)//2+H))
    bg = bg.filter(ImageFilter.GaussianBlur(38))
    bg = ImageEnhance.Brightness(bg).enhance(0.5)
    fg = asset.copy()
    s = min(safe[0]/fg.width, safe[1]/fg.height)
    fg = fg.resize((int(fg.width*s), int(fg.height*s)), Image.LANCZOS)
    box = ((W-fg.width)//2, (H-fg.height)//2)
    bg.paste(fg, box)
    return bg, (box[0], box[1], box[0]+fg.width, box[1]+fg.height)

def disclosure_in_frame(im, bottom=None, size_pct=0.016, pad=22):
    """The band that must survive an empty caption. Typeset INTO the frame, small, always.
    Anchored to the poster's own bottom edge, not the canvas, so a grid crop cannot remove it."""
    d = ImageDraw.Draw(im, "RGBA")
    fs = max(16, int(im.height*size_pct)); f = kr(fs, "Medium")
    y1 = im.height if bottom is None else bottom
    tw = d.textlength(DISCLOSURE, font=f)
    # A short right-hand pill, not a full-width bar: several posters already carry the wordmark
    # across the bottom, and a full bar covered it.
    d.rounded_rectangle([im.width-pad-tw-16, y1-fs-pad*2+4, im.width-pad+8, y1-4],
                        radius=6, fill=(15,29,19,165))
    d.text((im.width-pad-4, y1-pad-fs//2+2), DISCLOSURE, font=f, fill=BAND, anchor="rm")
    return im

def wordmark(im, mark, x, y, h=34, color_text="#FFFFFF"):
    d = ImageDraw.Draw(im)
    w = paste_mark(im, mark, x, y, h)
    d.text((x+w+14, y), "도그스하이", font=kr(int(h*0.82)), fill=color_text, anchor="lm")

# ================================================================ IG TILES
IG_W, IG_H = 1080, 1350
IG = [
 (1, None, "매니페스토", None),
 (2, "exec-2027525e-15b1-4dc3-9d62-cf497fd44342.png", "CHASE THAT HIGH.", True),
 (3, "exec-15c57834-8c8d-49a5-bc27-e5884b5bfbe0.png", "한 페이스 두 심장", True),
 (4, "exec-4ae213f9-1503-4645-8c35-9d8c0bdac5cc.png", "BORN TO RUN", True),
 (5, "film grain 2.png", "TWO HEARTS. ONE PACE.", True),
 (6, "exec-f8ab15af-ecdc-4c76-9592-bf3eec5f2deb.png", "오래 달릴 사이.", True),
 (7, "exec-729b5c4e-49e6-4cae-98e5-33da44bb3c17.png", "A TIRED DOG IS A HAPPY DOG.", True),
 (8, "exec-6cda8872-500b-4dfb-acc9-014c4e0bb4dd.png", "DOES YOUR DOG RUN?", True),
 (9, "exec-cb63cecf-8a86-4794-9ad3-5a35846c1431.png", "지금이야", True),
]

def tile_one(mark_w):
    """Tile 1 is built, not cropped: full-bleed dark anchor + wordmark + the manifesto line.
    Building it also sidesteps the swoosh on REMOVE NIKE.png entirely."""
    im = Image.new("RGB",(IG_W,IG_H), FOREST)
    d = ImageDraw.Draw(im)
    mw = paste_mark(im, mark_w, IG_W//2, int(IG_H*0.40), 240, anchor="cm")
    im.paste(mark_w.resize((0,0)) if False else Image.new("RGBA",(1,1),(0,0,0,0)),(0,0),Image.new("RGBA",(1,1),(0,0,0,0)))
    d.text((IG_W//2, int(IG_H*0.585)), "도그스하이", font=kr(112), fill="#FFFFFF", anchor="mm")
    d.text((IG_W//2, int(IG_H*0.665)), "DOGS HIGH", font=lat(30), fill=RED, anchor="mm")
    d.line([(IG_W//2-70, int(IG_H*0.715)), (IG_W//2+70, int(IG_H*0.715))], fill="#2A3A2F", width=2)
    d.text((IG_W//2, int(IG_H*0.775)), "두 개의 심장,", font=kr(44,"Medium"), fill="#E8ECE9", anchor="mm")
    d.text((IG_W//2, int(IG_H*0.828)), "하나의 러닝.", font=kr(44,"Medium"), fill="#E8ECE9", anchor="mm")
    return im

def paste_mark_center(canvas, mark, cx, cy, h):
    m = mark.copy(); w = int(m.width*h/m.height); m = m.resize((w,h), Image.LANCZOS)
    canvas.paste(m, (int(cx-w/2), int(cy-h/2)), m)

def build_ig(mark_w):
    d_out = ensure("ig"); made=[]
    for n, fn, label, ai in IG:
        if fn is None:
            im = Image.new("RGB",(IG_W,IG_H), FOREST); dd = ImageDraw.Draw(im)
            paste_mark_center(im, mark_w, IG_W//2, int(IG_H*0.38), 210)
            dd.text((IG_W//2, int(IG_H*0.575)), "도그스하이", font=kr(110), fill="#FFFFFF", anchor="mm")
            dd.text((IG_W//2, int(IG_H*0.655)), "DOGS HIGH", font=lat(28), fill=RED, anchor="mm")
            dd.line([(IG_W//2-70,int(IG_H*0.712)),(IG_W//2+70,int(IG_H*0.712))], fill="#2A3A2F", width=2)
            dd.text((IG_W//2, int(IG_H*0.775)), "두 개의 심장,", font=kr(46,"Medium"), fill="#E8ECE9", anchor="mm")
            dd.text((IG_W//2, int(IG_H*0.830)), "하나의 러닝.", font=kr(46,"Medium"), fill="#E8ECE9", anchor="mm")
        else:
            im, box = blur_bleed(Image.open(os.path.join(POST, fn)).convert("RGB"), IG_W, IG_H)
            if ai: disclosure_in_frame(im, bottom=box[3])
        p = os.path.join(d_out, f"{n:02d}.jpg"); im.save(p, quality=92); made.append((n,p,label))
    # Two grid previews. Instagram has shown both ratios; 1:1 is the worst case, so if the
    # composition holds there it holds anywhere. Do not guess which one is live — check both.
    for tag, (gw, gh) in (("GRID-1x1",(360,360)), ("GRID-3x4",(330,440))):
        g = Image.new("RGB",(gw*3+8*2, gh*3+8*2), "#FFFFFF")
        for i,(n,p,_) in enumerate(made):
            t = Image.open(p)
            s = min(t.width/gw, t.height/gh)
            cw, ch = int(gw*s), int(gh*s)
            t = t.crop(((t.width-cw)//2,(t.height-ch)//2,(t.width-cw)//2+cw,(t.height-ch)//2+ch)).resize((gw,gh), Image.LANCZOS)
            g.paste(t, ((i%3)*(gw+8), (i//3)*(gh+8)))
        g.save(os.path.join(d_out, tag+".jpg"), quality=90)
    return made

# ================================================================ TIKTOK
TT_W, TT_H = 1080, 1920
TOP, BOT = 200, 100

def tt_photo(fn, text, mark_w, show_wordmark=True, ai=True):
    im = Image.new("RGB",(TT_W,TT_H), FOREST)
    a = Image.open(os.path.join(POST, fn)).convert("RGB")
    inner_h = TT_H - TOP - BOT
    s = min(TT_W/a.width, inner_h/a.height)
    a2 = a.resize((int(a.width*s), int(a.height*s)), Image.LANCZOS)
    im.paste(a2, ((TT_W-a2.width)//2, TOP + (inner_h-a2.height)//2))
    d = ImageDraw.Draw(im)
    f = fit_font(text, TT_W-120, lambda s: kr(s), 62, 30)
    lines = wrap(text, f, TT_W-120, d)
    if len(lines) > 2:
        f = fit_font(text, TT_W-120, lambda s: kr(s), 44, 26); lines = wrap(text, f, TT_W-120, d)
    step = int(f.size*1.24); y = TOP//2 - (len(lines)-1)*step//2
    for i,l in enumerate(lines):
        d.text((TT_W//2, y+i*step), l, font=f, fill="#FFFFFF", anchor="mm")
    if show_wordmark: wordmark(im, mark_w, 44, TT_H-BOT//2, 30)
    if ai:
        d.text((TT_W-44, TT_H-BOT//2), DISCLOSURE, font=kr(24,"Medium"), fill=BAND, anchor="rm")
    return im

def tt_card(text, mark_w, kind="paper", sub=None, big=True, show_wordmark=True):
    bg  = {"paper":PAPER, "clay":CLAY, "forest":FOREST}[kind]
    fg  = "#FFFFFF" if kind=="forest" else INK
    dimc= "#8FA093" if kind=="forest" else DIM
    im = Image.new("RGB",(TT_W,TT_H), bg); d = ImageDraw.Draw(im)
    d.line([(80, 300),(TT_W-80, 300)], fill=LINE if kind!="forest" else "#24352a", width=2)
    f = kr(78 if big else 56)
    lines = wrap(text, f, TT_W-160, d)
    while len(lines) > 4 and f.size > 34:
        f = kr(f.size-6); lines = wrap(text, f, TT_W-160, d)
    step = int(f.size*1.30); y = TT_H//2 - (len(lines)-1)*step//2 - 60
    for i,l in enumerate(lines):
        d.text((80, y+i*step), l, font=f, fill=fg, anchor="lm")
    if sub:
        block(d, 80, y+len(lines)*step+40, sub, kr(34,"Medium"), dimc, TT_W-160, 1.4)
    if show_wordmark: wordmark(im, mark_w, 80, TT_H-140, 30, fg)
    return im

TS = {
 "TS-1": [("p","exec-6cda8872-500b-4dfb-acc9-014c4e0bb4dd.png","우리 개는 산책으론 안 빠져요",False),
          ("p","exec-729b5c4e-49e6-4cae-98e5-33da44bb3c17.png","끄는 개는 나쁜 개가 아닙니다",True),
          ("p","exec-50ed71e7-86a2-49a9-8bf8-d63a00d4619a.png","남은 에너지입니다",True),
          ("p","exec-15c57834-8c8d-49a5-bc27-e5884b5bfbe0.png","운동량으로만 빠지는 당김이 있습니다",True),
          ("p","exec-31d0246c-ca57-4fe5-9f6f-d346cce84b79.png","그걸 저희가 맡습니다",True),
          ("p","exec-f4103119-dd7f-41cb-be78-3ba0c5c28c31.png","인증 러너가 뛰고, GPS로 남습니다",True),
          ("c","forest","산책 말고, 러닝.","창립멤버 사전등록 — 프로필 링크")],
 "TS-2": [("c","forest","밤 11시에 거실을 도는 개",None),
          ("p","수건뺴고니온보이게.png","아침엔 문 앞에 두고 나갑니다",True),
          ("p","exec-2646005c-9e9b-44e6-a512-ab3d84b16071.png","못 뛰어준 날이 쌓입니다",True),
          ("p","dumb/ChatGPT Image Aug 4, 2026, 01_08_45 PM (1).png","— 오늘은 아니고요",True),
          ("p","dumb/ChatGPT Image Aug 4, 2026, 01_12_24 PM (3).png","인증 러너가 대신 뜁니다",True),
          ("p","exec-9db065c2-92ec-4264-9239-a035f055f886.png","기록이 남습니다",True),
          ("p","exec-f8ab15af-ecdc-4c76-9592-bf3eec5f2deb.png","지친 개, 조용한 저녁",True),
          ("c","forest","산책 말고, 러닝.","창립멤버 사전등록 — 프로필 링크")],
 "TS-3": [("p","exec-942fc070-709f-4a5b-8159-3bb0a1cb69ed.png","어차피 뛸 5km입니다",False),
          ("p","exec-f2abbd45-f4d9-4395-9292-d440b7a67708.png","페이가 붙을 뿐이고요",True),
          ("t",None,None,None),
          ("c","paper","시간당 얼마인지는 직접 계산해보세요","표를 통째로 공개합니다. 슬로건은 안 씁니다."),
          ("c","paper","보장은 안 합니다","수요는 동네 밀도에 따라 다릅니다."),
          ("p","exec-4ae213f9-1503-4645-8c35-9d8c0bdac5cc.png","초기 러너일수록 배정이 먼저 갑니다",True),
          ("p","exec-787fe7f3-1555-406d-8534-83af7294dc62.png","페이스 테스트 · 핸들링 · 승인",True),
          ("c","forest","뛰던 길에서, 벌자.","1기 인증 러너 모집 — 프로필 링크")],
 "TS-4": [("c","paper","러너 모집 공고는 보통 붙은 사람부터 보여줍니다",None),
          ("c","paper","순서를 바꿉니다",None),
          ("c","paper","① 5km 페이스 테스트",None),
          ("c","paper","② 반려견 핸들링 온보딩",None),
          ("c","paper","③ 승인 · ④ 배정",None),
          ("c","paper","넷 중 하나라도 안 되면 배정하지 않습니다",
           "보호자가 낯선 사람에게 개를 맡기는 서비스입니다.")],
 "TS-5": [("p","exec-cb63cecf-8a86-4794-9ad3-5a35846c1431.png","우리 개 에너지 테스트 — 몇 개?",False),
          ("c","clay","① 하루 운동 1시간 미만",None),
          ("c","clay","② 밤 11시에 거실을 돈다",None),
          ("c","clay","③ 산책 다녀와도 안 잔다",None),
          ("c","clay","④ “산책으론 안 빠져요”를 말해본 적 있다",None),
          ("p","exec-b10160bc-e30b-419a-91b6-f9472360978b.png","3개 이상이면 댓글에 견종 남겨주세요",True)],
 "TS-6": [("c","forest","사전주문 시작",None),
          ("p","film grain 2.png","출시일에 자동으로 설치됩니다",True),
          ("p","exec-6c5f7ae1-b1b4-4470-8867-84491236c736.png","인증 러너가 뛰고, 지도에 남습니다",True),
          ("c","paper","바디캠은 아직 준비 중입니다","준비되면 준비됐다고 말하겠습니다."),
          ("c","forest","한강 인근부터.","순서대로 엽니다.")],
}

def pay_card(mark_w):
    """The runner pay table. Figures come from runner-recruitment.md §1 at the decided 33% take
    rate and from nowhere else. Never rounded, never a slogan."""
    im = Image.new("RGB",(TT_W,TT_H), PAPER); d = ImageDraw.Draw(im)
    d.line([(80,300),(TT_W-80,300)], fill=LINE, width=2)
    d.text((80, 380), "러너 지급액", font=kr(52), fill=INK, anchor="lm")
    rows = [("5km 한 번", "16,683"), ("7km 한 번", "20,703"), ("5km 두 번 (연속)", "33,366")]
    y = 520
    for lab, val in rows:
        d.text((80, y), lab, font=kr(44,"Medium"), fill=DIM, anchor="lm")
        # Arial Black has no ₩ glyph — it renders as tofu. Digits stay in the display face,
        # the currency mark comes from the Korean face.
        fd = lat(58); fw = kr(52)
        d.text((TT_W-80, y), val, font=fd, fill=RED, anchor="rm")
        d.text((TT_W-80-d.textlength(val, font=fd)-8, y+2), "₩", font=fw, fill=RED, anchor="rm")
        d.line([(80,y+58),(TT_W-80,y+58)], fill=LINE, width=1)
        y += 130
    block(d, 80, y+40, "2026 최저임금 ₩10,320/시간. 인계 포함 시간으로 직접 나눠보세요.",
          kr(34,"Medium"), DIM, TT_W-160, 1.45)
    block(d, 80, y+180, "테이크레이트 33% 기준. 바뀌면 숫자를 먼저 고치고 다시 올립니다.",
          kr(30,"Medium"), DIM, TT_W-160, 1.45)
    wordmark(im, mark_w, 80, TT_H-140, 30, INK)
    return im

def build_tiktok(mark_w):
    made = {}
    for tid, slides in TS.items():
        dd = ensure("tiktok", tid); made[tid]=[]
        for i, s in enumerate(slides, 1):
            kind = s[0]
            if kind == "p":
                im = tt_photo(s[1], s[2], mark_w, show_wordmark=(i!=1), ai=s[3])
            elif kind == "t":
                im = pay_card(mark_w)
            else:
                im = tt_card(s[2], mark_w, kind=s[1], sub=s[3])
            p = os.path.join(dd, f"{i:02d}.jpg"); im.save(p, quality=90); made[tid].append(p)
    return made

def contact(paths, cols, out, cw=190):
    rows = (len(paths)+cols-1)//cols
    ch = int(cw*16/9)
    sheet = Image.new("RGB",(cols*(cw+8)+8, rows*(ch+30)+8), "#1a1a1a")
    d = ImageDraw.Draw(sheet)
    for i,p in enumerate(paths):
        t = Image.open(p); t.thumbnail((cw, ch))
        x = 8+(i%cols)*(cw+8); y = 8+(i//cols)*(ch+30)
        sheet.paste(t,(x + (cw-t.width)//2, y))
        d.text((x, y+ch+6), os.path.relpath(p, OUT), font=kr(13,"Medium"), fill="#ddd")
    sheet.save(out, quality=80)

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    mark_w = extract_mark("ChatGPT Image Aug 6, 2026, 08_50_21 PM.png", "mark-white.png")
    extract_mark("ChatGPT Image Aug 6, 2026, 08_34_03 PM.png", "mark-red.png")
    ig = build_ig(mark_w)
    tt = build_tiktok(mark_w)
    contact([p for _,p,_ in ig], 5, os.path.join(OUT,"CONTACT-ig.jpg"))
    allt = [p for v in tt.values() for p in v]
    contact(allt, 8, os.path.join(OUT,"CONTACT-tiktok.jpg"))
    print("IG tiles:", len(ig), "| TikTok slides:", len(allt))
