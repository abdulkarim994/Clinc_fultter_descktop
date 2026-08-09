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

  // ── (1) بطاقات العيادات بالخانات الثلاث ──────────────────────────────────

  testWidgets('بطاقة مستقلة لكل عيادة بخاناتها الثلاث بالأرقام الصحيحة',
      (tester) async {
    await boot(tester, seedFn: seed);

    // بطاقة العيادة موجودة.
    expect(find.byKey(const Key('tr-desk-clinic-ع1')), findsOneWidget);
    // الخانات الثلاث.
    expect(find.byKey(const Key('tr-desk-cash-ع1')), findsOneWidget);
    expect(find.byKey(const Key('tr-desk-xfer-ع1')), findsOneWidget);
    expect(find.byKey(const Key('tr-desk-pros-ع1')), findsOneWidget);

    // كاش = 120 + 80 + 100(دفعة دين ليلى الأولى كاش) = 300 (توأم
    // clinicCash الذي يضم regDebtPays)، تحويل = 300، التركيبات المدفوعة
    // = 3,000 (كامل الدين المسدّد بدفعتين).
    Text cellValue(String k) {
      final cell = find.descendant(
        of: find.byKey(Key(k)),
        matching: find.byWidgetPredicate(
            (w) => w is Text && (w.data ?? '').isNotEmpty),
      );
      return tester.widgetList<Text>(cell).firstWhere(
          (t) => t.data != 'كاش' && t.data != 'تحويل' &&
              t.data != 'تركيبات' && t.data != 'د.ل');
    }

    expect(cellValue('tr-desk-cash-ع1').data, '300');
    expect(cellValue('tr-desk-xfer-ع1').data, '300');
    expect(cellValue('tr-desk-pros-ع1').data, '3,000');
    expect(tester.takeException(), isNull);
  });

  // ── (2) النقر يفتح التفصيل بقائمة البنود + البحث يقلّص + إجمالي الفئة ──────

  testWidgets('نقر كاش يفتح التفصيل بقائمة البنود وإجمالي الفئة الصحيح',
      (tester) async {
    await boot(tester, seedFn: seed);

    // الحالة الفارغة أولاً (لا تفصيل).
    expect(find.text('اختر عملية لعرض التفاصيل'), findsOneWidget);

    // نقر خانة الكاش يفتح لوح التفصيل.
    await tester.tap(find.byKey(const Key('tr-desk-cash-ع1')));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('tr-desk-detail-list')), findsOneWidget);
    // العيادة والفئة في ترويسة التفصيل.
    expect(find.byKey(const Key('tr-desk-detail-clinic')), findsOneWidget);
    // بنود الكاش: أحمد + بدر (والدفعة الأولى من دين ليلى 100 كاش).
    expect(find.text('أحمد'), findsOneWidget);
    expect(find.text('بدر'), findsOneWidget);
    // إجمالي الفئة (كاش) = 120 + 80 + 100(دفعة دين ليلى) = 300.
    final total = tester.widget<Text>(
        find.byKey(const Key('tr-desk-detail-total')));
    expect(total.data, '300 د.ل');

    // البحث بالاسم «أحمد» يقلّص القائمة لعنصرٍ واحد. (نطاق البحث داخل
    // قائمة التفصيل فقط — النص يظهر أيضاً في حقل البحث نفسه بعد الكتابة.)
    await tester.enterText(
        find.byKey(const Key('tr-desk-search')), 'أحمد');
    await tester.pump(const Duration(milliseconds: 300));
    final inList = find.descendant(
      of: find.byKey(const Key('tr-desk-detail-list')),
      matching: find.text('أحمد'),
    );
    expect(inList, findsOneWidget);
    expect(find.text('بدر'), findsNothing);
    // إجمالي الفئة بعد التصفية = 120.
    final total2 = tester.widget<Text>(
        find.byKey(const Key('tr-desk-detail-total')));
    expect(total2.data, '120 د.ل');
    expect(tester.takeException(), isNull);
  });

  // ── (3) شريط الإجماليات السفلي: قبل/مصروفات/بعد بالأرقام الصحيحة ──────────

  testWidgets('شريط الإجماليات يعرض المحصّل والمصروفات والصوافي والديون',
      (tester) async {
    await boot(tester, seedFn: seed);

    // (أ) الدخل الفعلي المحصّل (قبل المصروفات) = كاش 300 + تحويل 300 +
    //     كامل التركيبة المدفوعة 3,000 = 3,600.
    final grand =
        tester.widget<Text>(find.byKey(const Key('tr-desk-grand')));
    expect(grand.data, '3,600 د.ل');

    // (ب) صف المصروفات: كاش 50، تحويل 0، الإجمالي 50.
    expect(
        tester
            .widget<Text>(find.byKey(const Key('tr-desk-exp-cash')))
            .data,
        '50');
    expect(
        tester
            .widget<Text>(find.byKey(const Key('tr-desk-exp-total')))
            .data,
        '50');

    // (ج) الصوافي: صافي الكاش = 300 − 50 = 250، صافي الخزينة = 3,600 − 50
    //     = 3,550.
    expect(
        tester
            .widget<Text>(find.byKey(const Key('tr-desk-cash-net')))
            .data,
        '250');
    expect(
        tester
            .widget<Text>(find.byKey(const Key('tr-desk-grand-net')))
            .data,
        '3,550 د.ل');

    // (د) ذيل الديون المعلقة = 400 (دين ليلى المتبقي).
    expect(find.byKey(const Key('tr-desk-open-debts')), findsOneWidget);
    expect(
        tester
            .widget<Text>(find.byKey(const Key('tr-desk-debt-rem')))
            .data,
        '400');
    expect(tester.takeException(), isNull);
  });

  // ── (3ب) ذيل الديون ينقل لتبويب الديون المكتبي ───────────────────────────

  testWidgets('نقر ذيل الديون المعلقة ينقل لتبويب الديون', (tester) async {
    await boot(tester, seedFn: seed);
    await tester.tap(find.byKey(const Key('tr-desk-open-debts')));
    await tester.pump(const Duration(milliseconds: 300));
    // انتقلنا لشاشة الديون المكتبية (تبويب الديون نشط).
    expect(find.byKey(const Key('desk-tab-debts')), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  // ── (4) زر الطباعة موجود في قمع الأدوات ──────────────────────────────────

  testWidgets('زر الطباعة موجود في قمع أدوات التفصيل', (tester) async {
    await boot(tester, seedFn: seed);
    await tester.tap(find.byKey(const Key('tr-desk-cash-ع1')));
    await tester.pump(const Duration(milliseconds: 300));

    // فتح قمع الأدوات.
    await tester.tap(find.byKey(const Key('tr-desk-tools')));
    await tester.pump(const Duration(milliseconds: 300));
    // عنصر الطباعة ظاهر.
    expect(find.byKey(const Key('tr-desk-print')), findsOneWidget);
    // وأنماط الفرز الأربعة موجودة.
    expect(find.byKey(const Key('tr-desk-sort-date-desc')), findsOneWidget);
    expect(find.byKey(const Key('tr-desk-sort-name-asc')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // ── (5) تفصيل التركيبات: المسار المجمّع الكامل كالهاتف ────────────────────

  testWidgets('تفصيل التركيبات: مجموعة المريض والحالة والدفعات المرقمة',
      (tester) async {
    await boot(tester, seedFn: seed);
    await tester.tap(find.byKey(const Key('tr-desk-pros-ع1')));
    await tester.pump(const Duration(milliseconds: 300));

    // تبويب التركيبات نشط.
    expect(find.byKey(const Key('tr-desk-cat-pros')), findsOneWidget);
    // بطاقة مجموعة المريض.
    expect(find.byKey(const Key('tr-desk-prosgroup-خالد')), findsOneWidget);

    // توسيع المجموعة يكشف الحالة والدفعتين المرقمتين.
    await tester.tap(find.byKey(const Key('tr-desk-prosgroup-خالد')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('دفعة 1'), findsOneWidget);
    expect(find.text('دفعة 2'), findsOneWidget);
    // مجاميع المجموعة: معمل 1,500 وطبيب 600 وعيادة 900 (أرقام اللقطة 40%).
    expect(find.text('1,500'), findsWidgets);
    expect(find.text('600'), findsWidgets);
    expect(find.text('900'), findsWidgets);
    // إجمالي الفئة (تركيبات) = مجموع حصص الطبيب = 600.
    final total = tester.widget<Text>(
        find.byKey(const Key('tr-desk-detail-total')));
    expect(total.data, '600 د.ل');
    expect(tester.takeException(), isNull);
  });

  // ── (6) بلا صلاحية treasury.details: «—» والبطاقات باقية ──────────────────

  testWidgets('بلا صلاحية treasury.details: الأرقام «—» والبطاقات تبقى',
      (tester) async {
    await boot(
      tester,
      seedFn: seed,
      // موظفٌ بلا treasury.details ⇒ الأرقام تُحجب لكن البطاقات تظهر.
      staff: <String, Object?>{
        'id': 'u1',
        'username': 'staff',
        'name': 'موظف مقيّد',
        'role': 'staff',
        'perms': <String, Object?>{'treasury.view': true},
      },
    );

    // البطاقة والخانات باقية.
    expect(find.byKey(const Key('tr-desk-clinic-ع1')), findsOneWidget);
    expect(find.byKey(const Key('tr-desk-cash-ع1')), findsOneWidget);
    expect(find.byKey(const Key('tr-desk-xfer-ع1')), findsOneWidget);
    expect(find.byKey(const Key('tr-desk-pros-ع1')), findsOneWidget);
    // م149 — مدخل «سجلات التحاليل الثلاثية» المستقل بدل الخانة الرابعة.
    expect(find.byKey(const Key('tr-desk-anal-registry')), findsOneWidget);

    // الأرقام «—» بدلاً من القيم (ثلاث خانات + إجمالي مدخل السجل).
    expect(find.text('—'), findsNWidgets(4));

    // بطاقة المحصّل والصوافي والديون محجوبة (خلف الصلاحية).
    expect(find.byKey(const Key('tr-desk-grand')), findsNothing);
    expect(find.byKey(const Key('tr-desk-cash-net')), findsNothing);
    expect(find.byKey(const Key('tr-desk-open-debts')), findsNothing);

    // صف المصروفات يظهر للجميع (مصروف كاش 50 مزروع).
    expect(find.byKey(const Key('tr-desk-exp-total')), findsOneWidget);

    // النقر لا يزال يفتح التفصيل (تفصيل متاح كالهاتف).
    await tester.tap(find.byKey(const Key('tr-desk-cash-ع1')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('tr-desk-detail-list')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
