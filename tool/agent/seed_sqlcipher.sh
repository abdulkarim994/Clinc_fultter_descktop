#!/usr/bin/env bash
# مهارة dental-clinic-build — زرع libsqlcipher (لينكس) لاختبارات الحاوية
#
# 🔴 حادثة APK 2180 (2026-08-14): النسخة الأولى من هذا السكربت كانت تدهس
# **كل** مجلدات hooks_runner/download-* بلا تمييز — بما فيها مكتبات
# **أندرويد** التي ينزّلها بناء APK في نفس المخبأ. النتيجة: حزمة أندرويد
# شحنت libsqlcipher بمعمارية x86-64 فرفضها الهاتف ⇒ شاشة رمادية عند
# الإقلاع. الدرس محفور هنا بقاعدتين:
#   ١) لا نلمس مجلداً إلا إذا كانت مكتبته الحالية **x86-64** أصلاً
#      (نقرأ بايتَي e_machine من ترويسة ELF قبل أي نسخ).
#   ٢) هذا الزرع لاختبارات لينكس فقط — **ممنوع تشغيله قبل بناء APK**؛
#      وإن سبق تشغيله في الجلسة فطهّر المخبأ قبل البناء:
#         rm -rf .dart_tool/hooks_runner build && flutter pub get
#
# العَرَض الذي يعالجه الزرع: فشل جماعي في flutter test باستثناءات Riverpod
# مضلِّلة (throwProviderException) — سببه الحقيقي أن مكتبة الهوك المنزّلة
# تطلب GLIBC_2.38 وحاوية الوكيل على 2.34.
#
# الاستعمال: bash seed_sqlcipher.sh /agent/workspace/repo
set -uo pipefail

REPO="${1:-/agent/workspace/repo}"
SRC="/tmp/sqlcipher-4.7.0/libsqlcipher.so"

[ -d "$REPO" ] || { echo "❌ مجلد المستودع غير موجود: $REPO"; exit 1; }
if [ ! -f "$SRC" ]; then
  echo "⚠️  $SRC غير موجودة — أبنيها الآن..."
  bash "$(dirname "$0")/build_sqlcipher.sh" || exit 1
fi

# معمارية ملف ELF من بايتَي e_machine (بلا اعتماد على أداة file).
#   3e00 = x86-64 (لينكس هنا) · b700 = AArch64 · 2800 = ARM32
elf_machine() {
  [ -f "$1" ] || { echo "absent"; return; }
  local m
  m=$(dd if="$1" bs=1 skip=18 count=2 2>/dev/null | od -An -tx1 | tr -d ' \n')
  case "$m" in
    3e00) echo "x86-64" ;;
    b700) echo "aarch64" ;;
    2800) echo "arm32" ;;
    *)    echo "unknown($m)" ;;
  esac
}

n=0; skipped=0

# 1) أصول لينكس الأصيلة — وجهة الزرع الشرعية الوحيدة بجانب الهوك.
if [ -d "$REPO/build/native_assets/linux" ]; then
  cp "$SRC" "$REPO/build/native_assets/linux/" \
    && { echo "✅ زُرعت: build/native_assets/linux/"; n=$((n+1)); }
else
  echo "ℹ️  build/native_assets/linux غير موجود بعد — سيُنشأ بعد أول flutter test"
fi

# 2) مجلدات تنزيل الهوك: **الحاوية لمكتبات x86-64 فقط** — أي معمارية
#    أخرى (أندرويد) تُترك بسلام ويُبلَّغ عنها.
shopt -s nullglob
for d in "$REPO"/.dart_tool/hooks_runner/shared/sqlite3/build/download-*/; do
  lib="$d/libsqlcipher.so"
  arch=$(elf_machine "$lib")
  case "$arch" in
    x86-64)
      cp "$SRC" "$lib" && { echo "✅ زُرعت (كانت x86-64): ${d#$REPO/}"; n=$((n+1)); } ;;
    absent)
      echo "ℹ️  بلا libsqlcipher (تُترك): ${d#$REPO/}"; skipped=$((skipped+1)) ;;
    *)
      echo "🛡️  مكتبة $arch (أندرويد؟) لا تُمس: ${d#$REPO/}"; skipped=$((skipped+1)) ;;
  esac
done

echo ""
if [ "$n" -gt 0 ]; then
  echo "🟢 زُرعت نسخة لينكس في $n موضعاً (وتُرك $skipped بسلام). الآن:"
  echo "   flutter analyze --fatal-warnings && flutter test"
  echo "⚠️  قبل أي بناء APK بعد هذا الزرع: طهّر المخبأ أولاً —"
  echo "   rm -rf .dart_tool/hooks_runner build && flutter pub get"
else
  echo "🟡 لم يُزرع شيء — المجلدات لم تُنشأ بعد أو كلها غير-x86-64."
  echo "   للاختبارات: شغّل اختباراً واحداً (سيفشل) ثم أعد هذا السكربت."
fi
