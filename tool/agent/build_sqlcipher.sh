#!/usr/bin/env bash
# مهارة dental-clinic-build — بناء libsqlcipher 4.7.0 من المصدر
#
# لماذا؟ النسخة التي ينزّلها هوك حزمة sqlite3 مبنيةٌ على glibc أحدث
# (تطلب GLIBC_2.38) وحاويات الوكيل على Amazon Linux 2023 فيها **2.34**.
# النتيجة: فشل جماعي في الاختبارات برسائل Riverpod مضلِّلة لا تذكر GLIBC.
#
# 🔴 تصحيح مهم (2026-08-13): بناء sqlcipher 4.7.0 صار autosetup:
#    • `--enable-tempstore` **أُلغي** — الصحيح `--with-tempstore=yes`
#    • لا يوجد خيار crypto مستقل — الأعلام تمرّ عبر CFLAGS
#    • الهدف اسمه `libsqlite3.so` ثم نعيد تسميته `libsqlcipher.so`
#
# الاستعمال: bash build_sqlcipher.sh   (النتيجة /tmp/sqlcipher-4.7.0/libsqlcipher.so)
set -euo pipefail

VER=4.7.0
DIR="/tmp/sqlcipher-${VER}"
OUT="${DIR}/libsqlcipher.so"

if [ -f "$OUT" ]; then
  echo "✅ موجودة سلفاً: $OUT ($(wc -c < "$OUT") بايت)"
  exit 0
fi

# أدوات البناء المطلوبة
for t in gcc make curl tar; do
  command -v "$t" >/dev/null || { echo "❌ $t غير مثبت — شغّل setup_toolchain.sh أولاً"; exit 1; }
done
[ -f /usr/include/openssl/ssl.h ] || { echo "❌ رؤوس openssl مفقودة (openssl-devel)"; exit 1; }

cd /tmp
if [ ! -d "$DIR" ]; then
  echo "── تنزيل المصدر ──"
  curl -sL --retry 3 -o "sqlcipher-${VER}.tar.gz" \
    "https://github.com/sqlcipher/sqlcipher/archive/refs/tags/v${VER}.tar.gz"
  tar xzf "sqlcipher-${VER}.tar.gz"
fi

cd "$DIR"
echo "── configure (صيغة autosetup الجديدة) ──"
./configure \
  --with-tempstore=yes \
  --disable-tcl \
  --fts5 \
  CFLAGS="-DSQLITE_HAS_CODEC -DSQLCIPHER_CRYPTO_OPENSSL -DSQLITE_EXTRA_INIT=sqlcipher_extra_init -DSQLITE_EXTRA_SHUTDOWN=sqlcipher_extra_shutdown -O2 -fPIC" \
  LDFLAGS="-lcrypto" > /tmp/sqlc_conf.log 2>&1 \
  || { echo "❌ فشل configure — آخر السطور:"; tail -15 /tmp/sqlc_conf.log; exit 1; }

echo "── make (دقيقة تقريباً على نواتين) ──"
make -j"$(nproc)" libsqlite3.so > /tmp/sqlc_make.log 2>&1 \
  || { echo "❌ فشل make — آخر السطور:"; tail -15 /tmp/sqlc_make.log; exit 1; }

cp libsqlite3.so "$OUT"

echo "── التحقق ──"
syms=$(nm -D "$OUT" 2>/dev/null | grep -c 'sqlite3_key\|sqlcipher' || true)
[ "$syms" -gt 0 ] && echo "✅ رموز التشفير موجودة ($syms رمزاً)" \
                  || { echo "❌ لا رموز sqlcipher — البناء بلا CODEC!"; exit 1; }
ldd "$OUT" | grep -q libcrypto && echo "✅ موصولة بـ libcrypto" \
                               || { echo "❌ غير موصولة بـ libcrypto"; exit 1; }
maxglibc=$(objdump -T "$OUT" 2>/dev/null | grep -o 'GLIBC_2\.[0-9]*' | sort -uV | tail -1)
echo "✅ أقصى GLIBC مطلوب: ${maxglibc:-غير معروف}  (glibc الحاوية: $(ldd --version | head -1 | grep -oE '[0-9]+\.[0-9]+$'))"
echo "🟢 جاهزة: $OUT ($(wc -c < "$OUT") بايت)"
echo "   الخطوة التالية: bash seed_sqlcipher.sh <repo>"
