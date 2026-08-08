#!/usr/bin/env bash
# ============================================================================
# بناء موصول بالسحابة (Supabase + R2)
#
#   الاستخدام:
#     ./tool/build_cloud.sh trial   <رقم_البناء>  ← تجريبية (معرّف جانبي)
#     ./tool/build_cloud.sh debug   <رقم_البناء>  ← نسخة debug موصولة
#     ./tool/build_cloud.sh release <رقم_البناء>  ← النشر الحقيقي
#     ./tool/build_cloud.sh windows <رقم_البناء>  ← بناء ويندوز
#
# م68/دفعة ثانٍ-أ — **أُخرجت الأسرار من هذا الملف.**
#
#   كانت القيم (رابط المشروع، ومفتاح anon صالح حتى 2036، ورابط عامل R2)
#   مكتوبةً هنا نصاً صريحاً وغيرَ مستثناةٍ من git. صحيحٌ أن مفتاح anon مصمَّم
#   للتضمين في العملاء، لكن كتابته في المستودع تعني أنه يسافر مع كل نسخة من
#   الأرشيف وكل استنساخ، ويبقى في تاريخ git بعد أي إزالة لاحقة.
#
#   القيم الآن تُقرأ من ملف بيئة **مستثنى من git**: tool/cloud.env
#   (انسخ tool/cloud.env.example واملأه). أو صدّرها متغيّراتِ بيئة بالأسماء
#   نفسها قبل النداء — مناسب لـ CI، والملف يصير اختيارياً حينها.
#
# ⚠ تذكير قائم: المفتاح الذي كان مكتوباً هنا سابقاً **يجب اعتباره مكشوفاً**.
#   دوّره من لوحة Supabase (Settings → API → Rotate). إزالته من الملف وحدها
#   لا تُبطله: هو باقٍ في تاريخ المستودع وفي كل نسخة وُزّعت.
# ============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${CLOUD_ENV_FILE:-$HERE/cloud.env}"

# 1) ملف البيئة إن وُجد (غير لازم عند التمرير من CI)
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  set -a; source "$ENV_FILE"; set +a
fi

# 2) التحقق من اكتمال القيم — الفشل مبكراً خيرٌ من نسخة صامتة بلا سحابة
missing=()
[[ -z "${SUPABASE_URL:-}"      ]] && missing+=(SUPABASE_URL)
[[ -z "${SUPABASE_ANON_KEY:-}" ]] && missing+=(SUPABASE_ANON_KEY)
if (( ${#missing[@]} )); then
  cat >&2 <<EOF
✖ قيم سحابية ناقصة: ${missing[*]}

  أنشئ ملف البيئة من المثال ثم املأه:
      cp tool/cloud.env.example tool/cloud.env
      \$EDITOR tool/cloud.env

  أو صدّرها متغيّراتِ بيئة قبل النداء (مناسب لـ CI).
  الملف tool/cloud.env مستثنى من git عمداً — لا تُضِفه.
EOF
  exit 1
fi

MODE="${1:-trial}"

# رقم البناء (versionCode): لا افتراضَ له عمداً.
#   الافتراض السابق كان 48 بينما المنشور v62 — فتشغيل السكربت بلا وسيط ينتج
#   versionCode أقدم، ويرفض أندرويد التثبيت برسالة عامة مضلِّلة.
BUILD_NUM="${2:-${BUILD_NUM:-}}"
if [[ -z "$BUILD_NUM" ]]; then
  echo "✖ مرّر رقم البناء: $0 $MODE <رقم_البناء>" >&2
  echo "  (لا افتراض له عمداً — رقمٌ أقدم من المنصَّب يجعل أندرويد يرفض التثبيت)" >&2
  exit 1
fi

VER=(--build-number="$BUILD_NUM" --build-name="1.0.$BUILD_NUM")
DEFINES=(
  --dart-define=SUPABASE_URL="$SUPABASE_URL"
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"
  --dart-define=R2_WORKER="${R2_WORKER:-}"
  --dart-define=PHONE_IDENTITY="${PHONE_IDENTITY:-1}"
  --dart-define=COLD_FETCH="${COLD_FETCH:-1}"
  # م88/ج — معرّف عميل الويب (عامّ بطبعه): يفعّل نافذة حسابات Google
  # الأصلية داخل التطبيق على أندرويد. فارغاً = مسار المتصفح وحده.
  --dart-define=GOOGLE_WEB_CLIENT_ID="${GOOGLE_WEB_CLIENT_ID:-}"
)
# تعتيم رموز Dart في نسخ الإصدار مع حفظ رموز التتبّع للتشخيص لاحقاً.
OBFUSCATE=(--obfuscate --split-debug-info=build/symbols)

case "$MODE" in
  trial)   ORG_GRADLE_PROJECT_trialSuffix=true flutter build apk --release --split-per-abi "${VER[@]}" "${DEFINES[@]}" "${OBFUSCATE[@]}" ;;
  debug)   flutter build apk --debug --split-per-abi "${VER[@]}" "${DEFINES[@]}" ;;
  release) flutter build apk --release --split-per-abi "${VER[@]}" "${DEFINES[@]}" "${OBFUSCATE[@]}" ;;
  windows) flutter build windows "${VER[@]}" "${DEFINES[@]}" ;;
  *) echo "الاستخدام: $0 [trial|debug|release|windows] <رقم_البناء>"; exit 1 ;;
esac
