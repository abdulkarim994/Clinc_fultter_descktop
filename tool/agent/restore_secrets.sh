#!/usr/bin/env bash
# مهارة dental-clinic-build — استعادة أسرار المشروع إلى أماكنها
#
# الاستعمال:
#   RunWithCredentials({skillName:'dental-clinic-build',
#     command:'bash skills/dental-clinic-build/restore_secrets.sh /agent/workspace/repo'})
#
# يكتب ثلاثة ملفات ثم يتحقق منها تحققاً حقيقياً (بصمة + أحجام + تغطية gitignore).
# لا يطبع أي قيمة سرّية — الطبع يقتصر على الأحجام والبصمات والحالة.
set -uo pipefail

REPO="${1:-/agent/workspace/repo}"
JKS_SHA1_EXPECTED="01:77:DE:51:F8:65:7A:62:A0:44:A0:B6:51:04:0C:7D:89:0F:B0:EB"
JKS_BYTES_EXPECTED=2616
fail=0

say()  { printf '%s\n' "$*"; }
bad()  { printf '❌ %s\n' "$*"; fail=1; }
good() { printf '✅ %s\n' "$*"; }

[ -d "$REPO" ] || { bad "مجلد المستودع غير موجود: $REPO"; exit 1; }

# ── 0) التأكد من وجود كل الحقول قبل الكتابة (لا نكتب ملفاً نصفه فارغ) ──────
need=(SUPABASE_URL SUPABASE_ANON_KEY R2_WORKER PHONE_IDENTITY COLD_FETCH
      GOOGLE_WEB_CLIENT_ID DENTAL_DEV_STORE_PASSWORD DENTAL_DEV_KEY_PASSWORD
      DENTAL_DEV_JKS_BASE64)
missing=()
for v in "${need[@]}"; do [ -n "${!v:-}" ] || missing+=("$v"); done
if [ ${#missing[@]} -gt 0 ]; then
  bad "حقول اعتماد ناقصة: ${missing[*]}"
  say "   افتح بطاقة المهارة واملأها، ثم أعد التشغيل."
  exit 1
fi
good "كل حقول الاعتماد التسعة موجودة"

mkdir -p "$REPO/tool" "$REPO/android/app"

# ── 1) tool/cloud.env — بتعليقاته الأصلية (توثيق قرارات لا ضجيج) ───────────
cat > "$REPO/tool/cloud.env" <<EOF
# tool/cloud.env — مستخرَج من .env.production لنسخة Vue (م74)
# ⚠ مستثنى من git. لا يُشارك ولا يُرفع.
SUPABASE_URL=${SUPABASE_URL}
# م84 — بُدّل المفتاح القديم (legacy anon JWT) بمفتاح publishable حديث.
#
#   القديم كان JWT صالحاً حتى 2036 لا يُبطَل إلا بإبطال **كل** المفاتيح
#   القديمة دفعةً واحدة، وقد سافر مع أرشيف المشروع. والحديث يُبطَل وحده
#   من اللوحة بلا مساس بغيره — وهذا هو الفرق العملي كله.
#
#   وقد تُحقِّق أنه بديلٌ مطابق على: تسجيل الدخول، والتسجيل، وPostgREST،
#   واستدعاء الدوال بجلسة وبلا جلسة — سلوكٌ واحد في الحالات الخمس.
SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}
R2_WORKER=${R2_WORKER}
# الأعلام تطابق الخلفية الإنتاجية — تغييرها يفصم هوية المرضى
PHONE_IDENTITY=${PHONE_IDENTITY}
COLD_FETCH=${COLD_FETCH}
GOOGLE_WEB_CLIENT_ID=${GOOGLE_WEB_CLIENT_ID}
EOF
chmod 600 "$REPO/tool/cloud.env"

# ── 2) tool/dev_keystore.env ───────────────────────────────────────────────
cat > "$REPO/tool/dev_keystore.env" <<EOF
# مخزن توقيع التطوير الجديد (وُلّد 2026-07-31 بعد تنحية المسرَّب)
# ⚠ مستثنى من git — لا يُشارك.
DENTAL_DEV_STORE_PASSWORD=${DENTAL_DEV_STORE_PASSWORD}
DENTAL_DEV_KEY_PASSWORD=${DENTAL_DEV_KEY_PASSWORD}
EOF
chmod 600 "$REPO/tool/dev_keystore.env"

# ── 3) android/app/dental_dev.jks من base64 ────────────────────────────────
printf '%s' "$DENTAL_DEV_JKS_BASE64" | tr -d '[:space:]' | base64 -d > "$REPO/android/app/dental_dev.jks" 2>/dev/null \
  || bad "فشل فك base64 للمخزن — الحقل DENTAL_DEV_JKS_BASE64 تالف؟"
chmod 600 "$REPO/android/app/dental_dev.jks"

say ""
say "── التحقق ─────────────────────────────────────────────────────────────"

# أحجام
for f in tool/cloud.env tool/dev_keystore.env android/app/dental_dev.jks; do
  if [ -s "$REPO/$f" ]; then good "$f — $(wc -c < "$REPO/$f") بايت"; else bad "$f فارغ أو غير موجود"; fi
done

# حجم المخزن يجب أن يطابق المعروف بالبايت
jks_bytes=$(wc -c < "$REPO/android/app/dental_dev.jks" 2>/dev/null || echo 0)
if [ "$jks_bytes" = "$JKS_BYTES_EXPECTED" ]; then
  good "حجم المخزن مطابق ($JKS_BYTES_EXPECTED بايت)"
else
  bad "حجم المخزن $jks_bytes ≠ المتوقع $JKS_BYTES_EXPECTED"
fi

# بصمة SHA-1 عبر keytool — الفحص الحقيقي الوحيد لصحة المخزن وكلمة مروره
KT=""
for cand in "${JAVA_HOME:-}/bin/keytool" /agent/jdk/bin/keytool "$(command -v keytool 2>/dev/null)"; do
  [ -n "$cand" ] && [ -x "$cand" ] && { KT="$cand"; break; }
done
if [ -n "$KT" ]; then
  got=$("$KT" -list -v -keystore "$REPO/android/app/dental_dev.jks" \
        -storepass "$DENTAL_DEV_STORE_PASSWORD" 2>/dev/null \
        | grep -oE 'SHA1: [0-9A-F:]+' | head -1 | sed 's/SHA1: //')
  if [ -z "$got" ]; then
    bad "keytool لم يقرأ المخزن — كلمة مرور المخزن خاطئة أو الملف تالف"
  elif [ "$got" = "$JKS_SHA1_EXPECTED" ]; then
    good "بصمة SHA-1 مطابقة: $got"
  else
    bad "بصمة SHA-1 مختلفة!"
    say "   المتوقع: $JKS_SHA1_EXPECTED"
    say "   الموجود: $got"
    say "   ⚠️ مخزن مختلف ⇒ التحديث فوق نسخ التجربة سيُرفَض على الأجهزة."
  fi
else
  say "⚠️  keytool غير متاح — تُخطّى بصمة SHA-1 (شغّل setup_toolchain.sh لتثبيت JDK)"
fi

# ── 4) حارس: الثلاثة يجب أن يكونوا مستثنين من git ──────────────────────────
if git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
  for f in tool/cloud.env tool/dev_keystore.env android/app/dental_dev.jks; do
    if git -C "$REPO" check-ignore -q "$f"; then
      good "مستثنى من git: $f"
    else
      bad "غير مستثنى من git: $f — لا ترفع شيئاً حتى تصلح .gitignore!"
    fi
  done
  # حارس إضافي: ألا يكون أيٌّ منها متتبَّعاً فعلاً
  if git -C "$REPO" ls-files --error-unmatch tool/cloud.env >/dev/null 2>&1; then
    bad "tool/cloud.env متتبَّع في git — أزله بـ git rm --cached فوراً"
  fi
  dirty=$(git -C "$REPO" status --porcelain | wc -l)
  [ "$dirty" -eq 0 ] && good "شجرة العمل نظيفة" || say "ℹ️  في الشجرة $dirty تغييراً غير مُلتزَم (طبيعي أثناء العمل)"
else
  say "⚠️  $REPO ليس مستودع git — تُخطّى حراس gitignore"
fi

say ""
if [ "$fail" -eq 0 ]; then
  say "🟢 الأسرار مستعادة ومتحقَّق منها. أمر البناء:"
  say "   set -a; source tool/dev_keystore.env; source tool/cloud.env; set +a"
  say "   ORG_GRADLE_PROJECT_trialSuffix=true ./tool/build_cloud.sh trial <BUILD_NUM>"
  exit 0
else
  say "🔴 فشل التحقق — راجع ❌ أعلاه ولا تبنِ قبل إصلاحها."
  exit 1
fi
