#!/usr/bin/env bash
# ============================================================
# توليد حمولة GitHub من مجلد المصدر (طريقة الأجزاء base64)
# الاستخدام:  ./make_payload.sh /path/to/src_app
# الناتج:     مجلد payload/ فيه proj.b64.part00..04 + بصمة التحقق
# ============================================================
set -euo pipefail
SRC="${1:?مرر مسار مجلد المشروع}"
cd "$SRC"
OUT="$(pwd)/../payload"; rm -rf "$OUT"; mkdir -p "$OUT"

# أرشيف نظيف: الملفات المتتبعة في git فقط (الأسرار غير متتبعة أصلاً)
git archive --format=zip -o "$OUT/proj.zip" HEAD
echo "sha256 (احفظه للتحقق): $(sha256sum "$OUT/proj.zip" | cut -d' ' -f1)"

# فحص أمان: لا مفاتيح داخل الأرشيف
if unzip -l "$OUT/proj.zip" | grep -qiE "\.jks|dev_keystore|/cloud\.env$"; then
  echo "⚠️ خطر: أسرار داخل الأرشيف — أوقف الرفع!" >&2; exit 1
fi
echo "✓ الأرشيف خالٍ من الأسرار"

cd "$OUT"
base64 -w 0 proj.zip > proj.b64
split -n 5 -d --additional-suffix= proj.b64 proj.b64.part
ls -la proj.b64.part*
echo "✓ ارفع الأجزاء الخمسة إلى _bootstrap/ في المستودع (استبدالاً)"
