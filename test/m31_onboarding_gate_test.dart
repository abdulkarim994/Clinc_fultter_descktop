/// اختبارات م31 — الإعداد الإلزامي وبوابة ما بعد الدخول:
///   • isAccountConfigured: يتطلب اسم مركز حقيقي (≠ الافتراضي) + عيادة+.
///   • isSetupComplete: بيانات ناقصة ⇒ غير مكتمل مهما كان العلم؛ بيانات
///     صحيحة وعلم غير مضبوط ⇒ ترحيل يضبط العلم.
///   • البوابة الإجبارية في الواجهة: حساب جديد ⇒ شاشة الإعداد، وإكمالها
///     يفتح الرئيسية؛ وتصمد عبر إعادة التشغيل (العلم دائم per-uid).
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/features/auth/onboarding_service.dart';
import 'package:dental_clinic_flutter/features/shell/app_shell.dart';
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('م31/1 — قاعدة الإعداد (نقية)', () {
    test('isAccountConfigured: الاسم الافتراضي أو بلا عيادة ⇒ غير مُعَدّ', () {
      expect(isAccountConfigured(null), isFalse);
      expect(isAccountConfigured({'centerName': '', 'clinics': ['ع']}),
          isFalse);
      expect(
          isAccountConfigured(
              {'centerName': 'طب الأسنان الرقمي', 'clinics': ['ع']}),
          isFalse,
          reason: 'الاسم الافتراضي لا يُعدّ إعداداً');
      expect(
          isAccountConfigured({'centerName': 'مركز', 'clinics': const []}),
          isFalse);
      expect(
          isAccountConfigured({'centerName': 'مركز', 'clinics': ['ع']}),
          isTrue);
    });
  });

  group('م31/2 — isSetupComplete والترحيل', () {
    late Directory tmp;
    late ProviderContainer c;
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('m31_');
      c = ProviderContainer(
          overrides: [dbDirProvider.overrideWithValue(tmp.path)]);
    });
    tearDown(() {
      c.dispose();
      tmp.deleteSync(recursive: true);
    });

    test('بيانات ناقصة ⇒ غير مكتمل ولو ضُبط العلم', () {
      final db = c.read(localDbProvider);
      markSetupComplete(db, 'u1');
      expect(isSetupComplete(db, 'u1', {'centerName': '', 'clinics': []}),
          isFalse);
    });

    test('بيانات صحيحة وعلم غير مضبوط ⇒ ترحيل يضبط العلم ويعدّه مكتملاً', () {
      final db = c.read(localDbProvider);
      expect(isSetupFlagSet(db, 'u2'), isFalse);
      final cfg = {'centerName': 'مركز', 'clinics': ['ع']};
      expect(isSetupComplete(db, 'u2', cfg), isTrue);
      expect(isSetupFlagSet(db, 'u2'), isTrue, reason: 'رُحّل العلم');
    });
  });

  group('م31/3 — البوابة الإجبارية في الواجهة', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('m31w_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    testWidgets('حساب جديد ⇒ شاشة الإعداد؛ إكمالها يفتح الرئيسية وتصمد',
        (tester) async {
      final seed = ProviderContainer(
          overrides: [dbDirProvider.overrideWithValue(tmp.path)]);
      final auth = seed.read(authServiceProvider);
      await auth.register('doc@clinic.ly', 'secret12');
      await auth.login('doc@clinic.ly', 'secret12', remember: true);
      seed.dispose();

      await tester.pumpWidget(ProviderScope(
        overrides: [dbDirProvider.overrideWithValue(tmp.path)],
        child: const DentalApp(),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // بوابة الإعداد الإجبارية (لا الرئيسية).
      expect(find.text('مرحباً بك'), findsOneWidget);
      expect(find.byType(AppShellScreen), findsNothing);

      // إكمال: اسم + عيادة ثم بدء التجهيز.
      await tester.enterText(
          find.byKey(const Key('gate-center-name')), 'مركز الأمل');
      await tester.enterText(
          find.byKey(const Key('gate-clinic-0')), 'العيادة أ');
      await tester.tap(find.byKey(const Key('gate-submit')));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 400));
      }
      expect(find.byType(AppShellScreen), findsOneWidget);

      // الإعداد حُفظ والعلم دائم ⇒ يصمد عبر إعادة تشغيل التطبيق.
      final chk = ProviderContainer(
          overrides: [dbDirProvider.overrideWithValue(tmp.path)]);
      addTearDown(chk.dispose);
      final cfg =
          chk.read(reposProvider).settings.get('app.config') as Map;
      expect(cfg['centerName'], 'مركز الأمل');
      expect(cfg['clinics'], ['العيادة أ']);
      expect(isSetupComplete(chk.read(localDbProvider), 'doc@clinic.ly',
          Map<String, Object?>.from(cfg)), isTrue);
    });

    testWidgets('نموذج الإعداد يمنع الحفظ بلا اسم مركز',
        (tester) async {
      final seed = ProviderContainer(
          overrides: [dbDirProvider.overrideWithValue(tmp.path)]);
      final auth = seed.read(authServiceProvider);
      await auth.register('doc@clinic.ly', 'secret12');
      await auth.login('doc@clinic.ly', 'secret12', remember: true);
      seed.dispose();

      await tester.pumpWidget(ProviderScope(
        overrides: [dbDirProvider.overrideWithValue(tmp.path)],
        child: const DentalApp(),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // عيادة بلا اسم مركز ⇒ خطأ، وتبقى شاشة الإعداد.
      await tester.enterText(
          find.byKey(const Key('gate-clinic-0')), 'ع1');
      await tester.tap(find.byKey(const Key('gate-submit')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const Key('gate-error')), findsOneWidget);
      expect(find.byType(AppShellScreen), findsNothing);
    });
  });
}
