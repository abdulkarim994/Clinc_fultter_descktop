/// اختبارات م87 — خيارات القفل والبصمة.
///
///  البصمةُ نفسها تحتاج عتاداً فلا تُختبَر على جهاز؛ لكن **كل ما حولها**
///  يُختبَر هنا: التفضيلات المحليّة، واحترام البوابة لمفتاح الإيقاف، ومنطق
///  «متى تُعرَض البصمة» و«ماذا يحدث عند نجاحها/فشلها» عبر مزيّفٍ في الذاكرة.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/features/auth/biometric_auth.dart';
import 'package:dental_clinic_flutter/features/auth/idle_lock.dart';
import 'package:dental_clinic_flutter/features/auth/lock_prefs.dart';
import 'package:dental_clinic_flutter/features/auth/onboarding_service.dart';
import 'package:dental_clinic_flutter/features/shell/app_shell.dart';
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// مزيّفٌ للبصمة: يُضبَط توفّرها ونتيجتها.
class _FakeBiometric implements BiometricAuth {
  _FakeBiometric({this.available = true, this.willSucceed = true});
  bool available;
  bool willSucceed;
  int authCalls = 0;
  @override
  Future<bool> isAvailable() async => available;
  @override
  Future<bool> authenticate(String reason) async {
    authCalls++;
    return willSucceed;
  }
}

void main() {
  group('م87/أ — تفضيلات القفل المحليّة', () {
    late Directory tmp;
    late ProviderContainer c;
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('m87a_');
      c = ProviderContainer(
          overrides: [dbDirProvider.overrideWithValue(tmp.path)]);
    });
    tearDown(() {
      c.dispose();
      tmp.deleteSync(recursive: true);
    });

    test('م97 — قفل الإقلاع معطَّل افتراضاً (الغياب = مُطفأ)', () {
      final db = c.read(localDbProvider);
      expect(lockOnStartEnabled(db), isFalse,
          reason: 'م97: القفل خدمةٌ يفعّلها المالك بعد تعيين رمزه');
    });

    test('البصمة معطَّلة افتراضاً (اختياريّة)', () {
      final db = c.read(localDbProvider);
      expect(biometricEnabled(db), isFalse);
    });

    test('التبديل يُحفَظ ويُقرأ', () {
      final db = c.read(localDbProvider);
      setLockOnStart(db, false);
      setBiometricEnabled(db, true);
      expect(lockOnStartEnabled(db), isFalse);
      expect(biometricEnabled(db), isTrue);
      setLockOnStart(db, true);
      expect(lockOnStartEnabled(db), isTrue);
    });
  });

  group('م87/ب — البوابة تحترم مفتاح الإيقاف', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('m87b_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    Future<void> seed({required bool lockOnStart}) async {
      final seed = ProviderContainer(
          overrides: [dbDirProvider.overrideWithValue(tmp.path)]);
      await seed.read(authServiceProvider).register('d@c.ly', 'secret12');
      await seed.read(authProvider.notifier).login('d@c.ly', 'secret12', true);
      final db = seed.read(localDbProvider);
      setLockOnStart(db, lockOnStart);
      seed.read(reposProvider).settings.set('app.config', {
        'centerName': 'مركز',
        'clinics': ['ع'],
      });
      markSetupComplete(db, 'd@c.ly');
      seed.dispose();
    }

    testWidgets('الإيقاف ⇒ فتحٌ مباشر بلا قفل', (tester) async {
      await seed(lockOnStart: false);
      await tester.pumpWidget(ProviderScope(
        overrides: [dbDirProvider.overrideWithValue(tmp.path)],
        child: const DentalApp(),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AppShellScreen), findsOneWidget);
      expect(find.byKey(const Key('idle-lock-title')), findsNothing,
          reason: 'م87: مفتاح الإيقاف يجعل الفتح مباشراً');
    });

    testWidgets('التفعيل (الافتراضي) ⇒ يبدأ مقفلاً', (tester) async {
      await seed(lockOnStart: true);
      await tester.pumpWidget(ProviderScope(
        overrides: [dbDirProvider.overrideWithValue(tmp.path)],
        child: const DentalApp(),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('idle-lock-title')), findsOneWidget);
    });
  });

  group('م87/ج — البصمة عبر مزيّف', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('m87c_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    Future<void> seedBiometric() async {
      final seed = ProviderContainer(
          overrides: [dbDirProvider.overrideWithValue(tmp.path)]);
      await seed.read(authServiceProvider).register('d@c.ly', 'secret12');
      await seed.read(authProvider.notifier).login('d@c.ly', 'secret12', true);
      final db = seed.read(localDbProvider);
      setBiometricEnabled(db, true); // مفعَّلة
      // م97 — القفل معطَّل افتراضاً؛ نفعّله صراحةً كي ينعقد قفلُ الإقلاع
      // فتُعرَض البصمة (مُتحقِّق كلمة المرور موجود من الدخول).
      setLockOnStart(db, true);
      seed.read(reposProvider).settings.set('app.config', {
        'centerName': 'مركز',
        'clinics': ['ع'],
      });
      markSetupComplete(db, 'd@c.ly');
      seed.dispose();
    }

    testWidgets('بصمةٌ ناجحة ترفع القفل بلا رمز', (tester) async {
      await seedBiometric();
      final fake = _FakeBiometric(available: true, willSucceed: true);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          dbDirProvider.overrideWithValue(tmp.path),
          biometricAuthProvider.overrideWithValue(fake),
        ],
        child: const DentalApp(),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // بدأ مقفلاً، والبصمة عُرضت فوراً فنجحت فرُفع القفل.
      expect(fake.authCalls, greaterThanOrEqualTo(1),
          reason: 'م87: البصمة تُطلَب فور القفل حين تكون مفعَّلة ومتاحة');
      expect(find.byKey(const Key('idle-lock-title')), findsNothing,
          reason: 'م87: نجاح البصمة يرفع القفل');
    });

    testWidgets('بصمةٌ فاشلة تُبقي الرمز بديلاً — لا حبس', (tester) async {
      await seedBiometric();
      final fake = _FakeBiometric(available: true, willSucceed: false);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          dbDirProvider.overrideWithValue(tmp.path),
          biometricAuthProvider.overrideWithValue(fake),
        ],
        child: const DentalApp(),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // فشلت ⇒ يبقى القفل وحقلُ الرمز حاضرٌ (بديلٌ دائم).
      expect(find.byKey(const Key('idle-lock-title')), findsOneWidget);
      expect(find.byKey(const Key('idle-lock-field')), findsOneWidget,
          reason: 'م87: الرمز يبقى متاحاً دائماً بعد فشل البصمة');
      // زرّ البصمة معروضٌ لإعادة المحاولة.
      expect(find.byKey(const Key('idle-lock-biometric')), findsOneWidget);
    });

    testWidgets('بصمةٌ غير متاحة ⇒ لا زرّ بصمة، الرمز فقط', (tester) async {
      await seedBiometric();
      final fake = _FakeBiometric(available: false);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          dbDirProvider.overrideWithValue(tmp.path),
          biometricAuthProvider.overrideWithValue(fake),
        ],
        child: const DentalApp(),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('idle-lock-title')), findsOneWidget);
      expect(fake.authCalls, 0, reason: 'م87: لا تُطلَب بصمةٌ غير متاحة');
      expect(find.byKey(const Key('idle-lock-biometric')), findsNothing);
    });
  });
}
