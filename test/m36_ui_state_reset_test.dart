/// اختبارات م36 — تصفير حالة الواجهة عند كل دخول/فتح + «الرئيسية»
/// التبويب الافتراضي (سيناريو لقطة rrk الحرفي):
///   دخول أ وفتح عيادة rrk داخل السجلات ⇒ خروج ⇒ دخول ب:
///   أول شاشة هي **الرئيسية** ولا وجود لـ rrk في أي إطار، وفتح
///   السجلات يعرض بوابة عيادات ب لا شاشة عيادة الحساب القديم.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/features/patients/patients_tab.dart'
    show openClinicProvider;
import 'package:dental_clinic_flutter/features/shell/app_shell.dart'
    show AppShellScreen, activeTabProvider;
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'staff_test_session.dart' show staffAdminSession;

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('m36_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  /// تجاوزات RenderFlex في إطارات الانتقال العابرة (عناصر DEFUNCT أثناء
  /// تبديل الحساب) ضوضاء تخطيط لا موضوع الاختبار (تصفير الحالة) — تُرشَّح.
  void ignoreTransientOverflow() {
    final old = FlutterError.onError;
    FlutterError.onError = (details) {
      if ('${details.exception}'.contains('RenderFlex overflowed')) {
        return;
      }
      old?.call(details);
    };
    addTearDown(() => FlutterError.onError = old);
  }

  Future<void> seedAccounts() async {
    final c = ProviderContainer(
      overrides: [
        staffAdminSession(),
        dbDirProvider.overrideWithValue(tmp.path),
      ],
    );
    final auth = c.read(authServiceProvider);
    await auth.register('a@clinic.ly', 'secret12');
    await auth.register('b@clinic.ly', 'secret12');
    await c.read(authProvider.notifier).login('a@clinic.ly', 'secret12', true);
    c.read(reposProvider).settings.set('app.config', {
      'centerName': 'مركز rrk',
      'clinics': ['rrk'],
      'services': ['حشو'],
      'payments': ['كاش'],
    });
    c.dispose();
  }

  /// م86 — إعادة الفتح على جلسةٍ محفوظة تبدأ مقفلة الآن. هذا الاختبار يقيس
  /// تصفير حالة الواجهة لا القفل، فيرفعه بكلمة المرور كما يفعل المستخدم.
  Future<void> unlockIfLocked(WidgetTester tester) async {
    if (find.byKey(const Key('idle-lock-field')).evaluate().isEmpty) return;
    await tester.enterText(
      find.byKey(const Key('idle-lock-field')),
      'secret12',
    );
    await tester.tap(find.byKey(const Key('idle-lock-unlock')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets(
    'سيناريو rrk: عيادة مفتوحة + تبويب السجلات لا يتسربان للحساب الجديد '
    'والرئيسية أولاً',
    (tester) async {
      ignoreTransientOverflow();
      await seedAccounts();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            staffAdminSession(),
            dbDirProvider.overrideWithValue(tmp.path),
          ],
          child: const DentalApp(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(AppShellScreen), findsOneWidget);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(AppShellScreen)),
      );

      // «الرئيسية» هي الافتراضية عند الفتح (كان الافتراضي السجلات).
      expect(container.read(activeTabProvider), 'home');
      await unlockIfLocked(tester); // م86 — إقلاعٌ بارد يبدأ مقفلاً

      // المستخدم أ: يفتح السجلات ثم عيادة rrk (حالة اللقطة حرفياً).
      await tester.tap(find.text('السجلات'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));
      container.read(openClinicProvider.notifier).state = 'rrk';
      await tester.pump(const Duration(milliseconds: 300));
      expect(container.read(activeTabProvider), 'clinics');

      // خروج ثم دخول ب داخل التطبيق الحي نفسه.
      await container.read(authProvider.notifier).logout();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await container
          .read(authProvider.notifier)
          .login('b@clinic.ly', 'secret12', true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      // البوابة صفّرت الحالة فوراً: التبويب رئيسية والعيادة المفتوحة زالت
      // — ولا أثر لـ rrk في أي إطار من هنا فصاعداً.
      expect(container.read(activeTabProvider), 'home');
      expect(container.read(openClinicProvider), isNull);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          find.text('rrk'),
          findsNothing,
          reason: 'عيادة الحساب القديم ظهرت بعد تبديل الحساب',
        );
      }

      // ب حساب جديد ⇒ شاشة الإعداد الإجبارية؛ نكملها لنبلغ الصدفة.
      await tester.enterText(
        find.byKey(const Key('gate-center-name')),
        'مركز عبدالكريم',
      );
      await tester.enterText(
        find.byKey(const Key('gate-clinic-0')),
        'العيادة الحقيقية',
      );
      await tester.tap(find.byKey(const Key('gate-submit')));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 400));
      }
      expect(find.byType(AppShellScreen), findsOneWidget);

      // أول شاشة بعد الدخول: «الرئيسية» النظيفة (نموذج إدخال جديد).
      expect(container.read(activeTabProvider), 'home');
      expect(find.text('rrk'), findsNothing);

      // فتح السجلات يعرض بوابة عيادات ب — لا شاشة عيادة قديمة مفتوحة.
      await tester.tap(find.text('السجلات'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));
      expect(container.read(openClinicProvider), isNull);
      expect(find.text('العيادة الحقيقية'), findsWidgets);
      expect(find.text('rrk'), findsNothing);
    },
  );

  testWidgets('فتح التطبيق باستعادة جلسة يبدأ بالرئيسية دائماً', (
    tester,
  ) async {
    ignoreTransientOverflow();
    await seedAccounts();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
        ],
        child: const DentalApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShellScreen)),
    );
    expect(container.read(activeTabProvider), 'home');
    await unlockIfLocked(tester); // م86 — يبدأ مقفلاً ثم يُرفع القفل
    // محتوى الرئيسية ظاهر فعلاً (زر اليوم/نموذج الإدخال).
    expect(find.text('الرئيسية'), findsWidgets);
  });
}
