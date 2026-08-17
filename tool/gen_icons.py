#!/usr/bin/env python3
"""م183 — مولّد أيقونات DENTSHINE من الشعار الرسمي الواحد.

يأخذ ملف الشعار المصدر (لوحة مربّعة بحوافّ مستديرة وإطار ذهبي وخلفية
خضراء تحمل الشعار المجرَّد واسم العلامة) ويولّد **كل** ما يحتاجه المشروع
دفعةً واحدة — فلا تتفرّق الأيقونات ولا تُنسى نسخةٌ عند تغيير الهوية.

═══ الدرس الذي وُلد منه هذا التصميم (حادثة أيقونة م182) ═══

وُضعت اللوحة الكاملة (بإطارها الذهبي وشريطها السفلي) أيقونةً تكيفيةً
بامتلاء 64٪، فظهرت على هاتف المالك (HyperOS/شاومي) **بخطوط مبتورة**:
قناع النظام يُظهر ما يقارب **منطقة الأمان وحدها** (≈64٪ من لوحة الأيقونة
التكيفية) ويقصّ ما بعدها — فقُصّ خطّا الإطار الرأسيان عند انحناء القناع،
وبُتر الشريط الكريمي السفلي.

**القاعدة المستخلَصة (وهي قاعدة أندرويد الرسمية):** أيقونة الإطلاق
**لا إطار لها**. خلفيةٌ تملأ من الحافة إلى الحافة (فلا شيء ليُقصّ) وفوقها
الشعار المجرَّد وحده داخل منطقة الأمان. لذلك يولّد هذا السكربت عائلتين:

  • **عائلة الإطلاق (مقنَّعة)** — أندرويد:
      drawable-*/ic_launcher_foreground.png   الشعار المجرَّد على شفافية
      mipmap-*/ic_launcher.png                نسخة مسطّحة (أندرويد < 8)
      والخلفية لونٌ متدرّج في drawable/ic_launcher_bg.xml (لا صورة).
  • **عائلة اللوحة الكاملة (بلا قناع)** — حيث لا يقصّها شيء:
      windows/runner/resources/app_icon.ico   أيقونة ويندوز
      assets/icon/icon-512.png                شاشة الدخول وداخل التطبيق

الاستعمال:
    python3 tool/gen_icons.py <ملف الشعار> [جذر المشروع]
"""

import sys
from pathlib import Path
from typing import Optional, Tuple

import numpy as np
from PIL import Image, ImageDraw

# ── حدود الشعار المجرَّد داخل اللوحة (نِسَبٌ لا بكسلات: تصمد لو تغيّر مقاس
# ملف المصدر). قيست على شعار DENTSHINE: حرف D والسن والبريق فوق الاسم.
EMBLEM_BOX = (0.25, 0.09, 0.80, 0.56)  # (x0, y0, x1, y1) نِسَباً من اللوحة

# عتبتا فصل الشعار عن الخلفية الخضراء (بالبعد اللوني): ما دون الأولى خلفيةٌ
# صرفة، وما فوق الثانية شعارٌ صرف، وبينهما تدرّجٌ ناعم يحفظ نعومة الحواف.
KEY_LO, KEY_HI = 25.0, 70.0

# نسبة الشعار من لوحة الأيقونة التكيفية (108dp). منطقة الأمان الرسمية
# 66dp/108dp ≈ 61٪، وقناع شاومي لا يُظهر أكثر منها — فـ46٪ تترك هامشاً
# مريحاً داخلها (يشغل الشعار ≈78٪ من المساحة الظاهرة على شاومي و≈69٪ على
# المشغّلات التي لا تكبّر). زيادتها تُلامس الحافة، ونقصانها تُقزّم الشعار.
ADAPTIVE_EMBLEM = 0.50

# ── م184 — التوسيط **البصري** لا الهندسي ────────────────────────────────
# توسيط صندوق الشعار يترك الهوامش متساوية لكن العين تراه مزاحاً: البريق
# الصغير أعلى اليمين (≈8٪ من مساحة الشعار) يمدّ الصندوق يميناً بينما كتلة
# الحرف D والسنّ كلها يساراً — فقِيس انحراف مركز الثقل 2.6٪–3.0٪ من الضلع
# (بلاغ المالك: «اللوغو ليس في وسط الصورة تماماً»). لذلك يُوضع الشعار
# بحيث يقع **مركز ثقله** على مركز اللوحة.
#
# الوزن = الشفافية × السطوع: الذهبي واللبني الساطعان يجذبان العين أكثر من
# الحوافّ الباهتة، فهذا أقرب لما تراه العين من وزن الشفافية وحده.
# القيمة 1.0 = توسيطٌ بصريٌّ تام، و0 = عودةٌ للتوسيط الهندسي القديم.
OPTICAL_CENTERING = 1.0

# النسخة المسطّحة (أندرويد < 8) لا يقصّها قناع: الشعار أكبر فيها.
LEGACY_EMBLEM = 0.60
LEGACY_RADIUS = 0.225  # نصف قطر زوايا المربّع (نسبة من الضلع)

MIPMAPS = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}
FOREGROUNDS = {
    'mdpi': 108, 'hdpi': 162, 'xhdpi': 216, 'xxhdpi': 324, 'xxxhdpi': 432,
}
ICO_SIZES = [16, 24, 32, 48, 64, 128, 256]


def load_tile(src: Path) -> Image.Image:
    """يقصّ اللوحة من مصدرها (بلا الظلّ الشفّاف حولها) ويجعلها مربّعة."""
    im = Image.open(src).convert('RGBA')
    # عتبة 200 تتجاهل الظلّ الناعم فتلتقط حدّ اللوحة نفسه.
    mask = im.getchannel('A').point(lambda v: 255 if v > 200 else 0)
    box = mask.getbbox()
    if box:
        im = im.crop(box)
    side = max(im.size)
    if im.size != (side, side):
        square = Image.new('RGBA', (side, side), (0, 0, 0, 0))
        square.paste(im, ((side - im.width) // 2, (side - im.height) // 2))
        im = square
    return im


def extract_emblem(tile: Image.Image) -> Tuple[Image.Image, Tuple[int, int, int]]:
    """يفصل الشعار المجرَّد عن خلفيته الخضراء، ويعيده مع لون تلك الخلفية.

    الفصل بالبعد اللوني عن الأخضر المرجعي (وسيط زوايا المنطقة): يعطي
    حوافّ ناعمة، ويجعل **جوف السن شفّافاً** — فتظهر خلفية الأيقونة من
    خلاله تماماً كما في اللوحة الأصلية.
    """
    w, h = tile.size
    x0, y0, x1, y1 = (round(v * (w if i % 2 == 0 else h))
                      for i, v in enumerate(EMBLEM_BOX))
    crop = np.array(tile.crop((x0, y0, x1, y1)), dtype=float)
    rgb = crop[..., :3]
    c = 60
    corners = np.concatenate([
        rgb[:c, :c].reshape(-1, 3), rgb[:c, -c:].reshape(-1, 3),
        rgb[-c:, :c].reshape(-1, 3), rgb[-c:, -c:].reshape(-1, 3),
    ])
    ref = np.median(corners, axis=0)
    dist = np.sqrt(((rgb - ref) ** 2).sum(axis=2))
    alpha = np.clip((dist - KEY_LO) / (KEY_HI - KEY_LO), 0, 1) * 255
    em = Image.fromarray(np.dstack([rgb, alpha]).astype(np.uint8))
    bb = em.getchannel('A').point(lambda v: 255 if v > 18 else 0).getbbox()
    if bb:
        em = em.crop(bb)
    return em, tuple(int(v) for v in ref.round())


def optical_offset(img: Image.Image) -> Tuple[float, float]:
    """إزاحة مركز الثقل البصري عن مركز الصورة (بالبكسل).

    الوزن = الشفافية × السطوع (انظر OPTICAL_CENTERING أعلاه). تُطرح هذه
    الإزاحة عند اللصق فيستقرّ مركز الثقل في منتصف اللوحة تماماً.
    """
    a = np.asarray(img.convert('RGBA'), dtype=float)
    lum = 0.2126 * a[..., 0] + 0.7152 * a[..., 1] + 0.0722 * a[..., 2]
    w = a[..., 3] * lum
    total = w.sum()
    if total <= 0:
        return 0.0, 0.0
    h, wd = w.shape
    ys, xs = np.mgrid[0:h, 0:wd]
    return ((xs * w).sum() / total - (wd - 1) / 2,
            (ys * w).sum() / total - (h - 1) / 2)


def place(emblem: Image.Image, size: int, fill: float,
          bg: Optional[Tuple] = None,
          radius: Optional[float] = None) -> Image.Image:
    """يضع الشعار في وسط لوحة `size` بنسبة `fill` من ضلعها.

    م184 — التوسيط **بصريّ**: يُزاح الشعار حتى يقع مركز ثقله على مركز
    اللوحة (بنسبة OPTICAL_CENTERING) بدل مساواة هوامش صندوقه.

    `bg=None` ⇒ لوحة شفّافة (مقدّمة تكيفية). وإلا خلفيةٌ مصمتة بزوايا
    مستديرة (النسخة المسطّحة لأندرويد القديم).
    """
    canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    if bg is not None:
        layer = Image.new('RGBA', (size, size), bg)
        if radius:
            mask = Image.new('L', (size, size), 0)
            ImageDraw.Draw(mask).rounded_rectangle(
                [0, 0, size - 1, size - 1], radius=round(size * radius),
                fill=255)
            layer.putalpha(mask)
        canvas.alpha_composite(layer)
    box = max(1, round(size * fill))
    em = emblem.copy()
    em.thumbnail((box, box), Image.LANCZOS)
    dx, dy = optical_offset(em)
    x = round((size - em.width) / 2 - dx * OPTICAL_CENTERING)
    y = round((size - em.height) / 2 - dy * OPTICAL_CENTERING)
    canvas.alpha_composite(em, (x, y))
    return canvas


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    src = Path(sys.argv[1])
    root = Path(sys.argv[2] if len(sys.argv) > 2 else '.')
    tile = load_tile(src)
    emblem, green = extract_emblem(tile)
    print(f'اللوحة: {tile.size[0]}×{tile.size[1]}  ·  '
          f'الشعار المجرَّد: {emblem.size[0]}×{emblem.size[1]}  ·  '
          f'الأخضر: #{green[0]:02X}{green[1]:02X}{green[2]:02X}')

    out = []

    def save(img: Image.Image, rel: str, **kw):
        p = root / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        img.save(p, **kw)
        out.append((rel, p.stat().st_size))

    # ── عائلة اللوحة الكاملة (بلا قناع) ──
    save(tile.resize((512, 512), Image.LANCZOS), 'assets/icon/icon-512.png')
    save(tile.resize((256, 256), Image.LANCZOS),
         'windows/runner/resources/app_icon.ico',
         format='ICO', sizes=[(s, s) for s in ICO_SIZES])

    # ── عائلة الإطلاق (مقنَّعة) ──
    save(place(emblem, 512, ADAPTIVE_EMBLEM), 'assets/icon/icon-foreground.png')
    for d, s in FOREGROUNDS.items():
        save(place(emblem, s, ADAPTIVE_EMBLEM),
             f'android/app/src/main/res/drawable-{d}/ic_launcher_foreground.png')
    for d, s in MIPMAPS.items():
        save(place(emblem, s, LEGACY_EMBLEM, bg=green + (255,),
                   radius=LEGACY_RADIUS),
             f'android/app/src/main/res/mipmap-{d}/ic_launcher.png')

    for rel, size in out:
        print(f'  ✅ {size:>8,} بايت  {rel}')
    print(f'المجموع: {len(out)} ملفاً')
    print(f'تذكير: لون خلفية الأيقونة التكيفية في '
          f'drawable/ic_launcher_bg.xml يجب أن يوافق '
          f'#{green[0]:02X}{green[1]:02X}{green[2]:02X}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
