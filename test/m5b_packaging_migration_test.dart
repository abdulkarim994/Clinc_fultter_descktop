/// اختبارات م5ب — ثوابت التغليف (هوية أندرويد/ويندوز المولدة).
/// م64 — أُزيلت مجموعات «الترحيل» (فحص القاعدة القديمة/التنفيذ/شاشة
/// الترحيل) بعد حذف ميزة السحابة والترحيل من التطبيق؛ يبقى فحص ثوابت
/// التغليف مستقلاً تماماً عن أي كود محذوف.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ثوابت التغليف', () {
    test('هوية أندرويد: المعرّف الأصلي والاسم العربي وإذن الإنترنت', () {
      final gradle =
          File('android/app/build.gradle.kts').readAsStringSync();
      expect(gradle, contains('applicationId = "com.dental.clinic"'));
      expect(gradle, contains('namespace = "com.dental.clinic"'));
      final manifest =
          File('android/app/src/main/AndroidManifest.xml')
              .readAsStringSync();
      expect(manifest, contains('android:label="DENTSHINE"'));
      expect(manifest, contains('android.permission.INTERNET'));
      expect(
          File('android/app/src/main/kotlin/com/dental/clinic/MainActivity.kt')
              .existsSync(),
          isTrue);
      expect(
          File('android/app/src/main/kotlin/com/dental/clinic/MainActivity.kt')
              .readAsStringSync(),
          contains('package com.dental.clinic'));
    });

    test('أيقونات مولدة + إعداد MSIX وعنوان نافذة ويندوز', () {
      expect(
          File('android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png')
              .existsSync(),
          isTrue);
      expect(File('windows/runner/resources/app_icon.ico').existsSync(),
          isTrue);
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('msix_config:'));
      expect(pubspec, contains('identity_name: com.dental.clinic'));
      expect(pubspec, contains('flutter_launcher_icons:'));
      final mainCpp =
          File('windows/runner/main.cpp').readAsStringSync();
      expect(mainCpp, contains('DENTSHINE'));
    });
  });
}
