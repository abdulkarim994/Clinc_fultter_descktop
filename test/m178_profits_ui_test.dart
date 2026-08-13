/// اختبارات م178 (واجهة) — قسم الأرباح المعاد بناؤه:
/// • ثلاث حبوب (الشهرية/السنوية/كشف الحساب) والكشف يفتح من حبته.
/// • الشهرية جداول: جدول العيادات + الإجمالي العام وفيه صف المصروفات
///   تحت عمود ربح العيادة ثم صافي ربح العيادة.
/// • السنوية: مؤشرات السنة + جدول الأرباح والخسائر (12 شهراً + إجمالي)
///   + جدول العيادات سنوياً.
/// • بطاقة «كشف الحساب» في قائمة المالية تفتح القسم الثالث (روابط م108).
/// • **لا مدخل للأرشيف بعد الآن** (fin-archive أُلغي).
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/core/utils/js_compat.dart'
    show getCurrentDate;
import 'package:dental_clinic_flutter/features/records/record_saver.dart'
    hide JMap;
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'staff_test_session.dart' show staffAdminSession;

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('m178ui_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Map<String, Object?> config() => {
        'centerName': 'مركز الاختبار',
        'clinics': ['ع1', 'ع2'],
        'services': ['حشو'],
        'payments': ['كاش', 'تحويل'],
        'doctorPct': 50,
      };

  final year = '${DateTime.now().year}';
  final month = '${DateTime.now().month}'.padLeft(2, '0');

  Future<void> boot(WidgetTester tester, {bool todayRow = false}) async {
    final c = ProviderContainer(
      overrides: [
        staffAdminSession(),
        dbDirProvider.overrideWithValue(tmp.path),
      ],
    );
    await c.read(authServiceProvider).register('doc@clinic.ly', 'secret12');
    await c
        .read(authProvider.notifier)
        .login('doc@clinic.ly', 'secret12', true);
    final repos = c.read(reposProvider);
    repos.settings.set('app.config', config());
    // الشهر الحالي: 1000 كاش ع1 + 400 تحويل ع2 ⇒ إيراد 1400،
    // طبيب 700، عيادة 700. ومصروف 100 ⇒ صافٍ 600.
    saveNewRecord(
      repos,
      config(),
      SaveRecordInput(
        name: 'أحمد',
        date: '$year-$month-05',
        amount: 1000,
        clinic: 'ع1',
        service: 'حشو',
        payment: 'كاش',
      ),
    );
    saveNewRecord(
      repos,
      config(),
      SaveRecordInput(
        name: 'هدى',
        date: '$year-$month-06',
        amount: 400,
        clinic: 'ع2',
        service: 'حشو',
        payment: 'تحويل',
      ),
    );
    repos.expenses.upsert({
      'id': 'exp-1',
      'date': '$year-$month-07',
      'amount': 100,
      'category': 'كهرباء',
      'payment': 'كاش',
    });
    // م178/ب — صف بتاريخ اليوم ليظهر في كشف الحساب (مداه الافتراضي
    // «اليوم»). يُطلب صراحةً كي لا تتغير أرقام اختبارات الشهرية.
    if (todayRow) {
      saveNewRecord(
        repos,
        config(),
        SaveRecordInput(
          name: 'نادر الشريف',
          date: getCurrentDate(),
          amount: 250,
          clinic: 'ع1',
          service: 'حشو',
          payment: 'كاش',
        ),
      );
    }
    c.dispose();
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
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(find.text('المالية'), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> openProfits(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const Key('fin-seg-profits')),
      warnIfMissed: false,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  String textOf(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(Key(key))).data!;

  group('م178 — الحبوب الثلاث', () {
    testWidgets('الشهرية والسنوية وكشف الحساب ظاهرة، ولا مدخل للأرشيف',
        (tester) async {
      await boot(tester);
      await openProfits(tester);
      expect(find.byKey(const Key('prof-view-monthly')), findsOneWidget);
      expect(find.byKey(const Key('prof-view-yearly')), findsOneWidget);
      expect(
          find.byKey(const Key('prof-view-statement')), findsOneWidget);
      // م178 — الأرشيف أُلغي بالكامل.
      expect(find.byKey(const Key('fin-archive')), findsNothing);
    });

    testWidgets('حبة كشف الحساب تعرض أدوات الكشف (st-*)', (tester) async {
      await boot(tester);
      await openProfits(tester);
      await tester.tap(find.byKey(const Key('prof-view-statement')),
          warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('st-search')), findsOneWidget);
      expect(find.byKey(const Key('st-range')), findsOneWidget);
      expect(find.byKey(const Key('st-total')), findsOneWidget);
    });

    testWidgets('بطاقة «كشف الحساب» بالقائمة تفتح القسم الثالث مباشرة',
        (tester) async {
      await boot(tester);
      await tester.tap(
        find.byKey(const Key('fin-seg-statement')),
        warnIfMissed: false,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // الكشف مفتوح وحبوب الأرباح حاضرة حوله.
      expect(find.byKey(const Key('st-search')), findsOneWidget);
      expect(
          find.byKey(const Key('prof-view-statement')), findsOneWidget);
    });
  });

  group('م178 — الشهرية جداول', () {
    testWidgets('جدول العيادات: صفا ع1 وع2 بأرقامهما', (tester) async {
      await boot(tester);
      await openProfits(tester);
      expect(find.byKey(const Key('prof-clinic-row-ع1')), findsOneWidget);
      expect(find.byKey(const Key('prof-clinic-row-ع2')), findsOneWidget);
    });

    testWidgets(
        'الإجمالي العام: 1400/700/700 والمصروفات 100 تحت عمود ربح '
        'العيادة والصافي 600', (tester) async {
      await boot(tester);
      await openProfits(tester);
      final scrollable = find
          .descendant(
            of: find.byKey(const Key('profits-section')),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.byKey(const Key('prof-grand-clinic-net')),
        200,
        scrollable: scrollable,
      );
      await tester.pump();
      expect(textOf(tester, 'prof-grand-revenue'), '1,400');
      expect(textOf(tester, 'prof-grand-doctor'), '700');
      expect(textOf(tester, 'prof-grand-clinic'), '700');
      // صف المصروفات: قيمته في عمود ربح العيادة (طرح عمودي مقروء).
      expect(textOf(tester, 'prof-grand-exp'), '100');
      expect(textOf(tester, 'prof-grand-clinic-net'), '600');
      // القيمة تحت العمود هندسياً: مركز خلية المصروفات يحاذي مركز
      // خلية ربح العيادة أفقياً (فرق أقل من نقطة).
      final cClinic =
          tester.getCenter(find.byKey(const Key('prof-grand-clinic')));
      final cExp =
          tester.getCenter(find.byKey(const Key('prof-grand-exp')));
      expect((cClinic.dx - cExp.dx).abs(), lessThan(1.0));
    });
  });

  group('م178/ب — كشف الحساب جدول الخزينة', () {
    Future<void> openStatement(WidgetTester tester) async {
      await openProfits(tester);
      await tester.tap(find.byKey(const Key('prof-view-statement')),
          warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('الأعمدة الستة بترتيب المالك (التاريخ أولاً)',
        (tester) async {
      await boot(tester, todayRow: true);
      await openStatement(tester);
      for (final h in [
        'التاريخ',
        'الاسم',
        'اسم العيادة',
        'نوع العلاج',
        'طريقة الدفع',
        'القيمة',
      ]) {
        expect(find.text(h), findsOneWidget, reason: 'ترويسة $h');
      }
      // ترتيب أفقي (RTL): التاريخ أيمن الأعمدة والقيمة أيسرها.
      final xDate = tester.getCenter(find.text('التاريخ')).dx;
      final xName = tester.getCenter(find.text('الاسم')).dx;
      final xClinic = tester.getCenter(find.text('اسم العيادة')).dx;
      final xService = tester.getCenter(find.text('نوع العلاج')).dx;
      final xPay = tester.getCenter(find.text('طريقة الدفع')).dx;
      final xVal = tester.getCenter(find.text('القيمة')).dx;
      expect(xDate, greaterThan(xName));
      expect(xName, greaterThan(xClinic));
      expect(xClinic, greaterThan(xService));
      expect(xService, greaterThan(xPay));
      expect(xPay, greaterThan(xVal));
    });

    testWidgets('العيادة صف عمودٍ لا شريط تجميع، والمجموع 250',
        (tester) async {
      await boot(tester, todayRow: true);
      await openStatement(tester);
      // صف الحركة: الاسم والعيادة والعلاج في صفٍّ واحد.
      expect(find.text('نادر الشريف'), findsOneWidget);
      expect(find.text('ع1'), findsOneWidget); // عمود العيادة
      expect(find.text('حشو'), findsOneWidget);
      // مجموع الجدول ومجموع التذييل متطابقان (250).
      expect(textOf(tester, 'st-table-total'), '250');
      expect(textOf(tester, 'st-total'), contains('250'));
    });

    testWidgets('لا حركات ⇒ رسالة الفراغ ولا جدول', (tester) async {
      await boot(tester); // بلا صف اليوم
      await openStatement(tester);
      expect(find.byKey(const Key('st-empty')), findsOneWidget);
      expect(find.byKey(const Key('st-table-total')), findsNothing);
    });
  });

  group('م178 — السنوية الجديدة', () {
    Future<void> openYearly(WidgetTester tester) async {
      await openProfits(tester);
      await tester.tap(find.byKey(const Key('prof-view-yearly')),
          warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('مؤشرات السنة: الإيراد والصافي والهامش', (tester) async {
      await boot(tester);
      await openYearly(tester);
      expect(textOf(tester, 'prof-year-grand'), contains('1,400'));
      // صافٍ = عيادة 700 − مصروفات 100 = 600.
      expect(textOf(tester, 'prof-year-net'), contains('600'));
      expect(textOf(tester, 'prof-year-exp'), contains('100'));
      // هامش = 600/1400 ≈ 42.9٪.
      expect(textOf(tester, 'prof-year-margin'), contains('42.9'));
    });

    testWidgets('جدول الأرباح والخسائر: 12 شهراً وصف إجمالي السنة',
        (tester) async {
      await boot(tester);
      await openYearly(tester);
      final scrollable = find
          .descendant(
            of: find.byKey(const Key('profits-year-section')),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.byKey(const Key('prof-pnl-total')),
        250,
        scrollable: scrollable,
      );
      await tester.pump();
      expect(find.byKey(const Key('prof-pnl-table')), findsOneWidget);
      expect(find.byKey(Key('prof-pnl-$year-$month')), findsOneWidget);
      expect(find.byKey(const Key('prof-pnl-total')), findsOneWidget);
    });

    testWidgets('جدول العيادات سنوياً يجمع أشهر السنة', (tester) async {
      await boot(tester);
      await openYearly(tester);
      final scrollable = find
          .descendant(
            of: find.byKey(const Key('profits-year-section')),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.byKey(const Key('prof-clinic-row-ع1')),
        250,
        scrollable: scrollable,
      );
      await tester.pump();
      expect(find.byKey(const Key('prof-clinic-row-ع1')), findsOneWidget);
      expect(find.byKey(const Key('prof-clinic-row-ع2')), findsOneWidget);
    });
  });
}
