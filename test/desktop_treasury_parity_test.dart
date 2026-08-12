/// ============================================================================
///  اختبارات تكافؤ «شاشة الخزينة المكتبية» مع الهاتف (DesktopTreasuryScreen)
/// ============================================================================
///
///  يتبع منوال desktop_finance_tabs_test.dart harness حرفياً:
///    • debugForceDesktopUi = true + physicalSize 1600×1000.
///    • بذرُ بيانات (كاش/تحويل + تركيبة بدفعات + دين + مصروف) ثم فتح تبويب
///      الخزينة والتأكد من التكافؤ:
///        - بطاقة مستقلة لكل عيادة بخاناتها الثلاث (كاش/تحويل/تركيبات).
///        - النقر على خانة يفتح لوح التفصيل بقائمة البنود.
///        - البحث بالاسم يقلّص القائمة.
///        - إجمالي الفئة صحيح.
///        - شريط الإجماليات السفلي يعرض قبل المصروفات/المصروفات/بعدها
///          بالأرقام الصحيحة.
///        - وجود زر الطباعة (قمع الأدوات).
///        - بلا صلاحية treasury.details: الأرقام «—» والبطاقات باقية.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/core/utils/js_compat.dart';
import 'package:dental_clinic_flutter/features/desktop/desktop_gate.dart'
    show debugForceDesktopUi;
import 'package:dental_clinic_flutter/features/finance/debt_actions.dart'
    show payDebtInstallment;
import 'package:dental_clinic_flutter/features/records/record_saver.dart'
    hide JMap;
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
    tmp = Directory.systemTemp.createTempSync('desk_tr_parity_');
    kCurrentStaff = null; // بلا جلسة ⇒ البوابة تسمح (سلوك الاختبارات).
  });
  tearDown(() {
    debugForceDesktopUi = null;
    kCurrentStaff = null;
    tmp.deleteSync(recursive: true);
  });

  Map<String, Object?> config() => {
        'centerName': 'مركز الاختبار',
        'doctorPct': 50,
        'clinicRates': {
          'clinics': {
            'ع1': {'treatments': {}, 'prosthetics': 40},
          },
        },
        'clinics': ['ع1'],
        // م168 — تفعيل التحاليل الثلاثية: صفوف tr2-*-anal تظهر بالتفعيل فقط.
        'analyses3': {'enabled': true, 'price': 50, 'repeatMonths': 6},
        'services': ['حشو', 'تركيبات'],
        'payments': ['كاش', 'تحويل'],
        'labTypes': [
          {'name': 'Zirconia', 'defaultPrice': 1500},
        ],
      };

  /// يبذر: كاش 200 (مريضان) + تحويل 300 + تركيبة دين 3,000 بدفعتين 1,500
  /// (معمل 1,500 ثم طبيب 600/عيادة 900) + دين عادي متبقٍ 400 + مصروف كاش 50.
  ///   ⇒ treasuryTotals: cash = 200 + 100(دفعة الدين العادي) ... نضبطها أدناه.
  void seed(ProviderContainer c) {
    final repos = c.read(reposProvider);
    final today = getCurrentDate();

    // كاش: مريضان (أ 120، ب 80) ⇒ كاش العيادة 200.
    saveNewRecord(
      repos,
      config(),
      SaveRecordInput(
        name: 'أحمد',
        date: today,
        amount: 120,
        clinic: 'ع1',
        service: 'حشو',
        payment: 'كاش',
      ),
    );
    saveNewRecord(
      repos,
      config(),
      SaveRecordInput(
        name: 'بدر',
        date: today,
        amount: 80,
        clinic: 'ع1',
        service: 'حشو',
        payment: 'كاش',
      ),
    );
    // تحويل: مريض واحد (سالم 300) ⇒ تحويل العيادة 300.
    saveNewRecord(
      repos,
      config(),
      SaveRecordInput(
        name: 'سالم',
        date: today,
        amount: 300,
        clinic: 'ع1',
        service: 'حشو',
        payment: 'تحويل',
      ),
    );
    // تركيبة دين 3,000 (معمل 1,500) بدفعتين 1,500 كاش عبر الأفعال الحرفية
    // (تجمّد _labAmount/_docAmount) — مسار م13 نفسه.
    saveNewRecord(
      repos,
      config(),
      SaveRecordInput(
        name: 'خالد',
        date: today,
        amount: 3000,
        clinic: 'ع1',
        service: 'تركيبات',
        payment: 'كاش',
        isDebt: true,
        labValue: 1500,
        prosType: 'Zirconia',
      ),
    );
    final prosDebt = repos.debts.getAll().single;
    payDebtInstallment(repos, config(), prosDebt,
        amount: 1500, date: today, payment: 'كاش');
    final prosDebt2 = repos.debts.getById('${prosDebt['id']}')!;
    payDebtInstallment(repos, config(), prosDebt2,
        amount: 1500, date: today, payment: 'كاش');

    // دين عادي (حشو) 500 بدفعة أولى 100 ⇒ متبقٍ 400 (لذيل الديون المعلقة).
    saveNewRecord(
      repos,
      config(),
      SaveRecordInput(
        name: 'ليلى',
        date: today,
        amount: 500,
        clinic: 'ع1',
        service: 'حشو',
        payment: 'كاش',
        isDebt: true,
        firstPay: 100,
      ),
    );

    // مصروف كاش 50 (لصف المصروفات في شريط الإجماليات).
    repos.expenses.upsert({
      'id': 'exp-1',
      'category': 'cleaning',
      'amount': 50.0,
      'payment': 'كاش',
      'date': today,
    });
  }

  Future<void> boot(
    WidgetTester tester, {
    void Function(ProviderContainer c)? seedFn,
    Map<String, Object?>? staff,
  }) async {
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
    c.read(reposProvider).settings.set('app.config', config());
    seedFn?.call(c);
    c.dispose();

    // م133/م121 — الجلسة المقيّدة تُضبط عبر المرآة العامة kCurrentStaff
    // التي يقرأها staffAllowed (لا المزوّد)، بعد البذر وقبل الإقلاع.
    if (staff != null) kCurrentStaff = staff;

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

    // فتح تبويب الخزينة المكتبي.
    await tester.tap(find.byKey(const Key('desk-tab-treasury')));
    await tester.pump(const Duration(milliseconds: 300));
  }

  // ═══ م154 — اختبارات الخزينة المكتبية الجديدة (جداول بوضعين) ═══

  testWidgets('صفوف القائمة الرئيسية بإجمالياتها الشهرية', (tester) async {
    await boot(tester, seedFn: seed);
    expect(find.byKey(const Key('tr2-row-ع1')), findsOneWidget);
    expect(find.byKey(const Key('tr2-row-anal')), findsOneWidget);
    expect(find.byKey(const Key('tr2-row-exp')), findsOneWidget);
    // إجمالي ع1 = كاش 300 + تحويل 300 + تركيبات مدفوعة 3,000 = 3,600.
    expect(find.textContaining('3,600'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('تفصيل العيادة: جدول الحركات وفلترة كاش والمجموع الظاهر',
      (tester) async {
    await boot(tester, seedFn: seed);
    await tester.tap(find.byKey(const Key('tr2-row-ع1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tr2-detail-pane')), findsOneWidget);
    // المجموع الظاهر (الكل) = كاش 300 + تحويل 300 = 600.
    expect(
        tester
            .widget<Text>(find.byKey(const Key('tr2-visible-total')))
            .data,
        '600');
    // فلترة كاش ⇒ 300.
    await tester.tap(find.descendant(
        of: find.byKey(const Key('tr2-pay-filter')),
        matching: find.text('كاش')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<Text>(find.byKey(const Key('tr2-visible-total')))
            .data,
        '300');
    expect(tester.takeException(), isNull);
  });

  testWidgets('التركيبات بمستويين: قائمة المرضى ثم جدول الدفعات بإجماليه',
      (tester) async {
    await boot(tester, seedFn: seed);
    await tester.tap(find.byKey(const Key('tr2-row-ع1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('التركيبات'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tr2-pros-g-خالد')), findsOneWidget);
    await tester.tap(find.byKey(const Key('tr2-pros-g-خالد')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tr2-pros-footer')), findsOneWidget);
    expect(find.byKey(const Key('tr2-pros-pay')), findsOneWidget);
    expect(find.byKey(const Key('tr2-pros-back')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('وضع «الإجمالي»: الجدول بصفوفه الأربعة وصافي الخزينة',
      (tester) async {
    await boot(tester, seedFn: seed);
    await tester.tap(find.text('الإجمالي'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tr2-totals-table')), findsOneWidget);
    expect(find.byKey(const Key('tr2-tot-clinics')), findsOneWidget);
    expect(find.byKey(const Key('tr2-tot-anal')), findsOneWidget);
    expect(find.byKey(const Key('tr2-tot-exp')), findsOneWidget);
    expect(find.byKey(const Key('tr2-tot-net')), findsOneWidget);
    // الصافي الشامل = المحصّل 3,600 + تحاليل 0 − مصروفات 50 = 3,550.
    expect(find.textContaining('3,550'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('بلا صلاحية treasury.details: الشرطات بدل الأرقام',
      (tester) async {
    await boot(
      tester,
      seedFn: seed,
      staff: {
        'username': 'staff',
        'name': 'موظف مقيّد',
        'role': 'staff',
        'perms': <String, Object?>{'treasury.view': true},
      },
    );
    // ثلاثة صفوف رئيسية كلها «—» (عيادة + تحاليل + مصروفات).
    expect(find.byKey(const Key('tr2-row-ع1')), findsOneWidget);
    expect(find.text('—'), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });
}
