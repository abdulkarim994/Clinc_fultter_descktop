#!/usr/bin/env bash
# مهارة dental-clinic-build — تهيئة حاوية جديدة من الصفر
#
# مُجرَّب فعلياً على Amazon Linux 2023 / glibc 2.34 / نواتين / 4GB (2026-08-13).
# المدة الكلية ~8-12 دقيقة (أثقلها Flutter 1.5GB وAndroid SDK).
#
# الاستعمال: bash setup_toolchain.sh
# ثم في كل جلسة صدفة جديدة:
#   export PATH="$PATH:/agent/flutter/bin"
#   export ANDROID_HOME=/agent/android-sdk JAVA_HOME=/agent/jdk
set -uo pipefail

FLUTTER_VERSION=3.44.8          # مثبّت في ci.yml بنفس الرقم — لا تغيّره
ANDROID_API=36
BUILD_TOOLS=36.0.0
CMDTOOLS_URL="https://dl.google.com/android/repository/commandlinetools-linux-13114758_latest.zip"

step() { printf '\n── %s ──\n' "$*"; }

step "1) سلسلة أدوات C وJDK"
# 🔴 لا يوجد java-17-openjdk في AL2023 — الاسم الصحيح java-17-amazon-corretto-devel
# (وضع الاسم الخاطئ يُفشل *كل* المعاملة فلا يُثبَّت gcc أيضاً!)
sudo dnf install -y -q \
  gcc make cmake ninja-build openssl-devel tcl unzip which pkgconf-pkg-config \
  java-17-amazon-corretto-devel || { echo "❌ فشل dnf"; exit 1; }

JH=$(ls -d /usr/lib/jvm/java-17-amazon-corretto* 2>/dev/null | head -1)
[ -n "$JH" ] && sudo ln -sfn "$JH" /agent/jdk
echo "✅ JDK: $(/agent/jdk/bin/java -version 2>&1 | head -1)"
echo "✅ gcc: $(gcc --version | head -1)"

step "2) شهادات الحاوية إلى cacerts (وإلا فشل sdkmanager/gradle بـ SSL)"
sudo chmod u+w "$JH/lib/security/cacerts" 2>/dev/null || true
for c in /etc/pki/ca-trust/source/anchors/*; do
  [ -f "$c" ] || continue
  sudo /agent/jdk/bin/keytool -importcert -noprompt -trustcacerts \
    -keystore "$JH/lib/security/cacerts" -storepass changeit \
    -alias "$(basename "$c")" -file "$c" >/dev/null 2>&1 \
    && echo "✅ أُضيفت: $(basename "$c")"
done

step "3) Flutter $FLUTTER_VERSION"
if [ -x /agent/flutter/bin/flutter ]; then
  echo "ℹ️  موجود سلفاً"
else
  curl -sL --retry 3 -o /tmp/flutter.tar.xz \
    "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
    || { echo "❌ فشل تنزيل Flutter"; exit 1; }
  tar xJf /tmp/flutter.tar.xz -C /agent
  rm -f /tmp/flutter.tar.xz
fi
export PATH="$PATH:/agent/flutter/bin"
git config --global --add safe.directory /agent/flutter 2>/dev/null || true
flutter --version | head -1
flutter --version | grep -q "Dart 3.12.2" \
  && echo "✅ Dart 3.12.2 — مطابق لقيد المشروع" \
  || echo "⚠️  نسخة Dart غير متوقعة — راجع قيد pubspec"

step "4) Android SDK (API $ANDROID_API + build-tools $BUILD_TOOLS)"
export ANDROID_HOME=/agent/android-sdk JAVA_HOME=/agent/jdk
if [ ! -x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" ]; then
  mkdir -p "$ANDROID_HOME/cmdline-tools"
  curl -sL --retry 3 -o /tmp/cmdtools.zip "$CMDTOOLS_URL"
  unzip -q -o /tmp/cmdtools.zip -d "$ANDROID_HOME/cmdline-tools"
  mv -f "$ANDROID_HOME/cmdline-tools/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest" 2>/dev/null || true
  rm -f /tmp/cmdtools.zip
fi
export PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin"
yes | sdkmanager --licenses >/dev/null 2>&1
sdkmanager "platform-tools" "platforms;android-${ANDROID_API}" "build-tools;${BUILD_TOOLS}" >/dev/null 2>&1 \
  && echo "✅ build-tools: $(ls "$ANDROID_HOME/build-tools/")" \
  || echo "❌ فشل sdkmanager (راجع الشهادات في الخطوة 2)"

step "5) libsqlcipher 4.7.0"
bash "$(dirname "$0")/build_sqlcipher.sh"

step "خلاصة"
flutter doctor 2>&1 | grep -E '^\[' | head -6
cat <<'EOS'

🟢 البيئة جاهزة. صدّر هذه في كل صدفة جديدة:
   export PATH="$PATH:/agent/flutter/bin"
   export ANDROID_HOME=/agent/android-sdk JAVA_HOME=/agent/jdk

الخطوات التالية داخل المستودع:
   flutter pub get
   bash skills/dental-clinic-build/seed_sqlcipher.sh <repo>   # إلزامي بعد pub get
   flutter analyze --fatal-warnings                            # No issues found
   flutter test                                                # +1326 ~57 (~11 دقيقة)

ملاحظتان مُجرَّبتان:
 • Chrome وLinux-desktop سيظهران ✗ في doctor — لا يهمّان (المنتج أندرويد + ويندوز).
 • لا تستعمل `pkill -f flutter_tester`: النمط يطابق أمرك نفسه فيقتل صدفتك
   (exit 144 وصفر إخراج). ولم يكن لازماً — الحزمة كاملةً تكفيها 1.8GB من 4GB.
EOS
