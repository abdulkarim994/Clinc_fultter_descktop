#!/usr/bin/env python3
"""م182 — مولّد أيقونات DENTSHINE من الشعار الرسمي الواحد.

يأخذ ملف الشعار المصدر (لوحة مربّعة بحوافّ مستديرة وإطار ذهبي وخلفية
خضراء) ويولّد **كل** الأشكال التي يحتاجها المشروع دفعةً واحدة، فلا
تتفرّق الأيقونات ولا تُنسى نسخةٌ عند تغيير الهوية:

  • assets/icon/icon-512.png            الشعار الكامل (المصدر داخل التطبيق
                                        — شاشة الدخول + flutter_launcher_icons)
  • assets/icon/icon-foreground.png     طبقة المقدّمة التكيفية (بهامش أمان)
  • mipmap-*/ic_launcher.png            الأيقونة القديمة (48…192)
  • drawable-*/ic_launcher_foreground   المقدّمة التكيفية (108…432)
  • windows/runner/resources/app_icon.ico  أيقونة ويندوز متعدّدة المقاسات

**حساب هامش الأمان (مهم):** `mipmap-anydpi-v26/ic_launcher.xml` يلفّ
المقدّمة بـ `inset=16%` من كل جهة، أي يتبقّى 68% من اللوحة. فنترك هنا
هامشاً صغيراً (6%) فقط، ليصير المحصّل النهائي ≈ 64% من لوحة الأيقونة
التكيفية — تظهر اللوحة كاملةً تحت أقنعة المربّع المستدير والـsquircle
(الغالبة على أندرويد)، ولا يُقصّ منها تحت القناع الدائري إلا أطراف
الإطار الذهبي. زيادة النسبة تقصّ النصّ، ونقصانها يصغّر الشعار بلا داعٍ.

الاستعمال:
    python3 tool/gen_icons.py <ملف الشعار> [جذر المشروع]
"""

import sys
from pathlib import Path

from PIL import Image

# نسبة امتلاء اللوحة داخل صورة المقدّمة (قبل inset الـ16% في XML).
FOREGROUND_FILL = 0.94

# مقاسات أندرويد: (اسم المجلد، المقاس).
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


def resized(tile: Image.Image, size: int) -> Image.Image:
    return tile.resize((size, size), Image.LANCZOS)


def foreground(tile: Image.Image, size: int) -> Image.Image:
    """اللوحة داخل لوحة شفّافة بهامش الأمان (يكملها inset الـXML)."""
    canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    inner = max(1, round(size * FOREGROUND_FILL))
    off = (size - inner) // 2
    canvas.paste(resized(tile, inner), (off, off))
    return canvas


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    src = Path(sys.argv[1])
    root = Path(sys.argv[2] if len(sys.argv) > 2 else '.')
    tile = load_tile(src)
    print(f'اللوحة المقصوصة: {tile.size[0]}×{tile.size[1]}')

    out = []

    def save(img: Image.Image, rel: str, **kw):
        p = root / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        img.save(p, **kw)
        out.append((rel, p.stat().st_size))

    save(resized(tile, 512), 'assets/icon/icon-512.png')
    save(foreground(tile, 512), 'assets/icon/icon-foreground.png')

    for d, s in MIPMAPS.items():
        save(resized(tile, s),
             f'android/app/src/main/res/mipmap-{d}/ic_launcher.png')
    for d, s in FOREGROUNDS.items():
        save(foreground(tile, s),
             f'android/app/src/main/res/drawable-{d}/ic_launcher_foreground.png')

    # ويندوز: ملفّ ico واحد يحمل كل المقاسات (المستكشف يختار الأنسب).
    save(resized(tile, 256), 'windows/runner/resources/app_icon.ico',
         format='ICO', sizes=[(s, s) for s in ICO_SIZES])

    for rel, size in out:
        print(f'  ✅ {size:>8,} بايت  {rel}')
    print(f'المجموع: {len(out)} ملفاً')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
