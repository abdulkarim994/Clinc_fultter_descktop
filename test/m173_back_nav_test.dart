/// م173 — زر رجوع النظام بالهاتف تسلسلاً هرمياً (قرار المالك):
///   • أي تبويبٍ غير الرئيسية ⇒ رجوعٌ للرئيسية أولاً (لا خروج مباشر).
///   • داخل عيادةٍ بالسجلات ⇒ رجوعٌ لبوابة العيادات ثم للرئيسية.
///   • الخزينة: تفاصيل حالة تركيبٍ ⇒ قائمة التركيبات ⇒ «الحركات» ⇒
///     شاشة الخزينة ⇒ الرئيسية — كلُّ رجوعٍ مستوىً واحداً.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/features/desktop/desktop_gate.dart';
import 'package:dental_clinic_flutter/features/patients/patients_tab.dart'
    show openClinicProvider;
import 'package:dental_clinic_flutter/features/shell/app_shell.dart'
    show activeTabProvider;
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'staff_test_session.dart' show staffAdminSession;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('m173b_'));
  tearDown(() {
    debugForceDesktopUi = null;
    tmp.deleteSync(recursive: true);
  });

  Future<ProviderContainer> bootShell(WidgetTester tester) async {
    debugForceDesktopUi = false;
    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final s = ProviderContainer(overrides: [
      staffAdminSession(),
      dbDirProvider.overrideWithValue(tmp.path),
    ]);
    final auth = s.read(authServiceProvider);
    await auth.register('doc@clinic.ly', 'secret12');
    await auth.login('doc@clinic.ly', 'secret12', remember: true);
    s.read(reposProvider).settings.set('app.config', {
      'centerName': 'م',
      'clinics': ['ع1'],
      'services': ['حشو'],
      'payments': ['كاش'],
    });
    final repos = s.read(reposProvider);
    // تركيبة بدفعة — لجدول تركيبات الخزينة (المستويان).
    final now = DateTime.now();
    final ym = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}';
    repos.prosthetics.upsertLocal({
      'id': 'p1',
      'name': 'وليد',
      'date': '$ym-01',
      'work': 'زركون',
      'total': 500,
      'paid': 200,
      'payment': 'كاش',
      'lab': 'مخبر',
      'labCost': 100,
      'clinic': 'ع1',
      '_t': 'p',
    });
    s.dispose();
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
    await tester.pump(const Duration(milliseconds: 300));
    final ok = find.byKey(const Key('appt-notif-ok'));
    if (ok.evaluate().isNotEmpty) {
      await tester.tap(ok);
      await tester.pump(const Duration(milliseconds: 200));
    }
    return ProviderScope.containerOf(
      tester.element(find.byType(DentalApp)),
      listen: false,
    );
  }

  /// محاكاة زر رجوع النظام (يمر بمسار maybePop وPopScope الحقيقي).
  Future<void> back(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }

  testWidgets('تبويب غير الرئيسية: رجوعٌ يعود للرئيسية لا خروجاً',
      (tester) async {
    final c = await bootShell(tester);
    await tester.tap(find.text('المالية'));
    await tester.pumpAndSettle();
    expect(c.read(activeTabProvider), 'finance');

    await back(tester);
    expect(c.read(activeTabProvider), 'home',
        reason: 'الرجوع من تبويبٍ يعيد للرئيسية أولاً');
    expect(find.byType(DentalApp), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('داخل عيادة: رجوعٌ للبوابة ثم رجوعٌ للرئيسية',
      (tester) async {
    final c = await bootShell(tester);
    await tester.tap(find.text('السجلات'));
    await tester.pumpAndSettle();
    c.read(openClinicProvider.notifier).state = 'ع1';
    await tester.pumpAndSettle();

    await back(tester);
    expect(c.read(openClinicProvider), isNull,
        reason: 'الرجوع الأول يغلق العيادة (بوابة العيادات)');
    expect(c.read(activeTabProvider), 'clinics');

    await back(tester);
    expect(c.read(activeTabProvider), 'home');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'الخزينة: التركيبات ⇒ الحركات ⇒ الخزينة ⇒ الرئيسية بكل رجوع',
      (tester) async {
    final c = await bootShell(tester);
    // فتح المالية ⇒ الخزينة ⇒ تفصيل العيادة.
    await tester.tap(find.text('المالية'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fin-seg-treasury')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('treasury-main')), findsOneWidget);
    await tester.tap(find.byKey(const Key('tr2-row-ع1')));
    await tester.pumpAndSettle();

    // تبويب «التركيبات» داخل التفصيل.
    await tester.tap(find.text('التركيبات'));
    await tester.pumpAndSettle();
    expect(find.text('وليد'), findsWidgets);

    // رجوع 1: التركيبات ⇒ الحركات (نفس الشاشة).
    await back(tester);
    expect(find.textContaining('حركات'), findsWidgets,
        reason: 'عاد لتبويب الحركات داخل شاشة التفصيل');

    // رجوع 2: مغادرة التفصيل ⇒ شاشة الخزينة.
    await back(tester);
    expect(find.byKey(const Key('treasury-main')), findsOneWidget);

    // رجوع 3: مغادرة الخزينة ⇒ الرئيسية مباشرةً (قرار المالك).
    await back(tester);
    expect(c.read(activeTabProvider), 'home');
    expect(find.byKey(const Key('treasury-main')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('تفاصيل حالة تركيبٍ مفتوحة: الرجوع يغلقها أولاً',
      (tester) async {
    await bootShell(tester);
    await tester.tap(find.text('المالية'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fin-seg-treasury')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tr2-row-ع1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('التركيبات'));
    await tester.pumpAndSettle();

    // فتح تفاصيل حالة «وليد» (المستوى الثاني).
    await tester.tap(find.text('وليد').first, warnIfMissed: false);
    await tester.pumpAndSettle();

    // رجوع: تُغلق التفاصيل أولاً — نبقى في جدول التركيبات.
    await back(tester);
    expect(find.text('وليد'), findsWidgets,
        reason: 'عاد لقائمة التركيبات لا للحركات');
    // رجوعٌ آخر: التركيبات ⇒ الحركات.
    await back(tester);
    expect(find.textContaining('حركات'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
