/// م151 — اختبار واجهة «إدخال اليوم» المكتبي: ✓ واحدة لكل مريضٍ أجرى
/// التحليل (لا لكل صفوفه)، وخانات المال تتبدل بأوضاع فلتر التحاليل
/// الخمسة بأرقام المواصفة، ويعاد حسابها فور تبديل الفلتر.
///
/// البذر (مثال المواصفة ٩ موسّعاً): أحمد بثلاث زيارات كاش (100/50/30)
/// وتحليل 25 كاش مرتبط بالزيارة الثانية؛ سالم زيارة تحويل 100؛ خالد
/// زيارة كاش 40 وتحليل 50 تحويل — فالمتوقع:
///   «الكل»            245 / 150 / 395 (الإيراد + التحاليل مرة واحدة)
///   «تحاليل كاش»      25 / 0 / 25
///   «تحاليل تحويل»    0 / 50 / 50
///   «إجمالي التحاليل» 25 / 50 / 75
///   «بلا تحاليل»      130 / 100 / 230 (بلا الصفوف الحاملة للعلامة)
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/core/utils/js_compat.dart'
    show getCurrentDate;
import 'package:dental_clinic_flutter/features/desktop/desktop_gate.dart'
    show debugForceDesktopUi;
import 'package:dental_clinic_flutter/features/records/record_saver.dart';
import 'package:dental_clinic_flutter/features/staff/staff_session.dart'
    show kCurrentStaff;
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'staff_test_session.dart' show staffAdminSession;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('m151_');
    kCurrentStaff = null;
  });
  tearDown(() {
    debugForceDesktopUi = null;
    kCurrentStaff = null;
    tmp.deleteSync(recursive: true);
  });

  Map<String, Object?> config() => {
        'centerName': 'مركز الاختبار',
        'clinics': ['الصفوة'],
        'services': ['حشو'],
        'payments': ['كاش', 'تحويل'],
        'analyses3': {'enabled': true, 'price': 25, 'repeatMonths': 6},
      };

  Future<void> boot(WidgetTester tester) async {
    debugForceDesktopUi = true;
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final c = ProviderContainer(overrides: [
      staffAdminSession(),
      dbDirProvider.overrideWithValue(tmp.path),
    ]);
    final auth = c.read(authServiceProvider);
    await auth.register('doc@clinic.ly', 'secret12');
    await auth.login('doc@clinic.ly', 'secret12', remember: true);
    final repos = c.read(reposProvider);
    repos.settings.set('app.config', config());
    final today = getCurrentDate();

    String visit(String name, num amount, String pay) => saveNewRecord(
          repos,
          config(),
          SaveRecordInput(
            name: name,
            date: today,
            amount: amount,
            clinic: 'الصفوة',
            service: 'حشو',
            payment: pay,
          ),
        ).entryId;

    // أحمد: ثلاث زيارات كاش — التحليل مرتبط بالثانية حصراً.
    visit('أحمد', 100, 'كاش');
    final ahmad2 = visit('أحمد', 50, 'كاش');
    visit('أحمد', 30, 'كاش');
    // سالم: تحويل 100 بلا تحليل. خالد: كاش 40 وتحليله تحويل 50.
    visit('سالم', 100, 'تحويل');
    final khaled = visit('خالد', 40, 'كاش');

    // صفّا التحليل خامان بمعرّفين فريدين (قيمتان مختلفتان عمداً —
    // الكاتب الموحد يثبّت سعر الإعدادات، والاختبار يريد 25 و50).
    void seedAnal(String id, String name, String of, num amount, String pay) =>
        repos.records.upsertLocal({
          'id': id,
          'isAnalysis': 1,
          'name': name,
          'patient_name': name,
          'amount': amount,
          'payment': pay,
          'clinic': 'الصفوة',
          'clinic_id': 'الصفوة',
          'date': today,
          'service': 'تحاليل',
          'isDebt': 0,
          'isPros': 0,
          'isDebtPayment': 0,
          'analysisName': 'التحاليل الثلاثية',
          'analysisOf': of,
          '_t': 'r',
        });
    seedAnal('anal-1', 'أحمد', ahmad2, 25, 'كاش');
    seedAnal('anal-2', 'خالد', khaled, 50, 'تحويل');
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
    await tester.pump(const Duration(milliseconds: 300));
    // تبويب «الرئيسية» (جدول إدخال اليوم) هو الافتراضي — نضمنه صراحةً.
    await tester.tap(find.byKey(const Key('desk-tab-home')));
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// نص خانة لوحة الملخص (dash-cash/dash-transfer/dash-paid) — القيمة
  /// تُرسم Text.rich فيُقرأ نصها المسطّح من textSpan لا من data.
  String cell(WidgetTester t, String key) {
    final texts = t.widgetList<Text>(find.descendant(
      of: find.byKey(ValueKey(key)),
      matching: find.byType(Text),
    ));
    return [
      for (final x in texts) x.data ?? x.textSpan?.toPlainText() ?? '',
    ].join('|');
  }

  Future<void> pickFilter(WidgetTester t, String name) async {
    await t.tap(find.byKey(const Key('desk-anal-filter')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(Key('desk-anal-filter-$name')));
    await t.pumpAndSettle();
  }

  testWidgets('✓ واحدة لكل مريضٍ أجرى التحليل وأوضاع الملخص الخمسة صحيحة',
      (tester) async {
    await boot(tester);

    // (١) علامتا ✓ فقط (أحمد وخالد) رغم خمسة صفوف — لا تكرار بالصفوف.
    expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(2),
        reason: '✓ = عدد المرضى الذين أجروا التحاليل لا عدد الصفوف');

    // (٢) «الكل»: الإيراد + التحاليل مرة واحدة = 245 / 150 / 395.
    expect(cell(tester, 'dash-cash'), contains('245'));
    expect(cell(tester, 'dash-transfer'), contains('150'));
    expect(cell(tester, 'dash-paid'), contains('395'));

    // (٣) «تحاليل كاش»: قيم التحاليل وحدها = 25 / 0 / 25.
    await pickFilter(tester, 'cash');
    expect(cell(tester, 'dash-cash'), contains('25'));
    expect(cell(tester, 'dash-transfer'), contains('0'));
    expect(cell(tester, 'dash-paid'), contains('25'));

    // (٤) «تحاليل تحويل»: 0 / 50 / 50.
    await pickFilter(tester, 'transfer');
    expect(cell(tester, 'dash-cash'), contains('0'));
    expect(cell(tester, 'dash-transfer'), contains('50'));
    expect(cell(tester, 'dash-paid'), contains('50'));

    // (٥) «إجمالي التحاليل»: 25 / 50 / 75 — والجدول يعرض صفَّي الحاملَين.
    await pickFilter(tester, 'totals');
    expect(cell(tester, 'dash-cash'), contains('25'));
    expect(cell(tester, 'dash-transfer'), contains('50'));
    expect(cell(tester, 'dash-paid'), contains('75'));
    expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(2));

    // (٦) «بلا تحاليل»: الصفوف غير الحاملة فقط = 130 / 100 / 230.
    await pickFilter(tester, 'none');
    expect(cell(tester, 'dash-cash'), contains('130'));
    expect(cell(tester, 'dash-transfer'), contains('100'));
    expect(cell(tester, 'dash-paid'), contains('230'));
    expect(find.byIcon(Icons.check_circle_rounded), findsNothing);

    // (٧) العودة إلى «الكل» تعيد الحساب فوراً.
    await pickFilter(tester, 'all');
    expect(cell(tester, 'dash-paid'), contains('395'));
    expect(tester.takeException(), isNull);
  });
}
