/// اختبارات م14 — قسم الديون طبق الأصل:
///   • وحدات: forgiveDebt (الإجمالي = المدفوع، انعكاس على التركيبة بحصص
///     اللقطة وعلى السجل الأصلي)، cancelDebtInstallment (عكس المبالغ
///     والحالة وإعادة اشتقاق labPaid/doctorEarned، شاهدة ناعمة، حذف سجل
///     الدفعة)، installmentsForDisplay (الأحدث أولاً بأرقام ثابتة).
///   • واجهة: بنية البطاقة التوأم (شارات/أعمدة/نسبة السداد/الأزرار)،
///     حبوب الحالة، فلتر العيادة من قائمة القمع وشارته، نافذة سجل
///     الدفعات بإلغاء النقرتين، والمسامحة بالتأكيد المزدوج.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/core/utils/js_compat.dart';
import 'package:dental_clinic_flutter/features/finance/debt_actions.dart'
    show payDebtInstallment, forgiveDebt, cancelDebtInstallment;
import 'package:dental_clinic_flutter/features/finance/treasury_logic.dart'
    show activeInstallments, installmentsForDisplay;
import 'package:dental_clinic_flutter/features/records/record_saver.dart'
    hide JMap;
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'staff_test_session.dart' show staffAdminSession;

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('m14_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Map<String, Object?> config() => {
    'centerName': 'مركز الاختبار',
    'doctorPct': 50,
    'clinicRates': {
      'clinics': {
        'الصفوة': {'treatments': {}, 'prosthetics': 40},
      },
    },
    'clinics': ['الصفوة', 'ع2'],
    'services': ['حشو عصب', 'تركيبات'],
    'payments': ['كاش', 'تحويل'],
    'labTypes': [
      {'name': 'Zirocnia', 'defaultPrice': 1500},
    ],
  };

  ProviderContainer container() => ProviderContainer(
    overrides: [staffAdminSession(), dbDirProvider.overrideWithValue(tmp.path)],
  );

  group('الوحدات — المسامحة', () {
    test('دين عادي: الإجمالي يصبح المدفوع والسجل الأصلي يتبعه', () {
      final c = container();
      addTearDown(c.dispose);
      final repos = c.read(reposProvider);
      saveNewRecord(
        repos,
        config(),
        SaveRecordInput(
          name: 'هند',
          date: getCurrentDate(),
          amount: 550,
          clinic: 'الصفوة',
          service: 'حشو عصب',
          payment: 'كاش',
          isDebt: true,
          firstPay: 400,
        ),
      );
      final debt = repos.debts.getAll().single;
      final newTotal = forgiveDebt(repos, config(), '${debt['id']}');
      expect(newTotal, 400);
      final d = repos.debts.getAll().single;
      expect(jsNumOr0(jsOr(d['totalAmount'], d['total'])), 400);
      expect(jsNumOr0(d['remaining']), 0);
      expect(d['status'], 'paid');
      // السجل الأصلي المرتبط اتّبع الإجمالي الجديد.
      final origin = repos.records.getAll().firstWhere(
        (r) => !jsTruthy(r['isDebtPayment']),
      );
      expect(jsNumOr0(origin['amount']), 400);
      // مسامحة دين مسدد: لا شيء.
      expect(forgiveDebt(repos, config(), '${d['id']}'), isNull);
    });

    test('دين تركيبة: الحصص تُعاد من نسبة اللقطة على الصافي الجديد', () {
      final c = container();
      addTearDown(c.dispose);
      final repos = c.read(reposProvider);
      saveNewRecord(
        repos,
        config(),
        SaveRecordInput(
          name: 'Khlgg',
          date: getCurrentDate(),
          amount: 3000,
          clinic: 'الصفوة',
          service: 'تركيبات',
          payment: 'كاش',
          isDebt: true,
          labValue: 1500,
          prosType: 'Zirocnia',
        ),
      );
      var debt = repos.debts.getAll().single;
      payDebtInstallment(
        repos,
        config(),
        debt,
        amount: 2000,
        date: getCurrentDate(),
        payment: 'كاش',
      );
      debt = repos.debts.getAll().single;
      final newTotal = forgiveDebt(repos, config(), '${debt['id']}');
      // الإجمالي الجديد = المدفوع 2,000؛ الصافي 500 بنسبة اللقطة 40%:
      // طبيب 200 وعيادة 300.
      expect(newTotal, 2000);
      final pros = repos.prosthetics.getAll().single;
      expect(jsNumOr0(pros['total']), 2000);
      expect(jsNumOr0(pros['doctorShare']), 200);
      expect(jsNumOr0(pros['clinicShare']), 300);
      final d = repos.debts.getAll().single;
      expect(d['status'], 'paid');
      expect(jsNumOr0(d['remaining']), 0);
    });
  });

  group('الوحدات — إلغاء دفعة', () {
    test('عادي: عكس المبالغ والحالة وحذف سجل الدفعة وشاهدة القسط', () {
      final c = container();
      addTearDown(c.dispose);
      final repos = c.read(reposProvider);
      saveNewRecord(
        repos,
        config(),
        SaveRecordInput(
          name: 'هند',
          date: getCurrentDate(),
          amount: 300,
          clinic: 'الصفوة',
          service: 'حشو عصب',
          payment: 'كاش',
          isDebt: true,
          firstPay: 100,
        ),
      );
      var debt = repos.debts.getAll().single;
      final res = payDebtInstallment(
        repos,
        config(),
        debt,
        amount: 200,
        date: getCurrentDate(),
        payment: 'كاش',
      );
      debt = repos.debts.getAll().single;
      expect(debt['status'], 'paid');
      final inst = activeInstallments(
        debt,
      ).firstWhere((el) => '${el['recordId']}' == res.payRecordId);
      final activeBefore = activeInstallments(debt).length;

      final done = cancelDebtInstallment(
        repos,
        config(),
        '${debt['id']}',
        '${inst['id']}',
      );
      expect(done, isTrue);
      final d = repos.debts.getAll().single;
      expect(jsNumOr0(d['paidAmount']), 100);
      expect(jsNumOr0(d['remaining']), 200);
      expect(d['status'], 'partial');
      // القسط شاهدة ناعمة (يبقى في المصفوفة) وسجل الدفعة حُذف.
      expect(activeInstallments(d).length, activeBefore - 1);
      expect((d['installments'] as List).length, activeBefore);
      expect(repos.records.getById(res.payRecordId), isNull);
      // إلغاء معرّف غير موجود: لا شيء.
      expect(
        cancelDebtInstallment(repos, config(), '${d['id']}', 'zzz'),
        isFalse,
      );
    });

    test('تركيبة: labPaid وdoctorEarned يُشتقّان من جديد بنسبة العيادة', () {
      final c = container();
      addTearDown(c.dispose);
      final repos = c.read(reposProvider);
      saveNewRecord(
        repos,
        config(),
        SaveRecordInput(
          name: 'Khlgg',
          date: getCurrentDate(),
          amount: 3000,
          clinic: 'الصفوة',
          service: 'تركيبات',
          payment: 'كاش',
          isDebt: true,
          labValue: 1500,
          prosType: 'Zirocnia',
        ),
      );
      var debt = repos.debts.getAll().single;
      payDebtInstallment(
        repos,
        config(),
        debt,
        amount: 2000,
        date: getCurrentDate(),
        payment: 'كاش',
      );
      debt = repos.debts.getAll().single;
      final res2 = payDebtInstallment(
        repos,
        config(),
        debt,
        amount: 1000,
        date: getCurrentDate(),
        payment: 'كاش',
      );
      debt = repos.debts.getAll().single;
      expect(debt['status'], 'paid');

      // إلغاء دفعة الإقفال 1,000: المدفوع 2,000 ⇒ معمل 1,500 وربح 500
      // بنسبة تركيبات الصفوة 40% ⇒ طبيب 200.
      final inst = activeInstallments(
        debt,
      ).firstWhere((el) => '${el['recordId']}' == res2.payRecordId);
      cancelDebtInstallment(repos, config(), '${debt['id']}', '${inst['id']}');
      final d = repos.debts.getAll().single;
      expect(jsNumOr0(d['paidAmount']), 2000);
      expect(jsNumOr0(d['remaining']), 1000);
      expect(d['status'], 'partial');
      expect(jsNumOr0(d['labPaid']), 1500);
      expect(jsNumOr0(d['doctorEarned']), 200);
      expect(repos.records.getById(res2.payRecordId), isNull);
    });

    test('installmentsForDisplay: الأحدث أولاً بأرقام كرونولوجية ثابتة', () {
      final c = container();
      addTearDown(c.dispose);
      final repos = c.read(reposProvider);
      saveNewRecord(
        repos,
        config(),
        SaveRecordInput(
          name: 'هند',
          date: getCurrentDate(),
          amount: 300,
          clinic: 'الصفوة',
          service: 'حشو عصب',
          payment: 'كاش',
          isDebt: true,
        ),
      );
      var debt = repos.debts.getAll().single;
      payDebtInstallment(
        repos,
        config(),
        debt,
        amount: 100,
        date: '2026-07-01',
        payment: 'كاش',
      );
      debt = repos.debts.getAll().single;
      payDebtInstallment(
        repos,
        config(),
        debt,
        amount: 200,
        date: '2026-07-20',
        payment: 'تحويل',
      );
      debt = repos.debts.getAll().single;
      final disp = installmentsForDisplay(debt, repos.records.getAll());
      expect(disp, hasLength(2));
      // الأحدث (الثانية كرونولوجياً) أولاً وتحمل «دفعة 2».
      expect(jsNumOr0(disp[0]['seq']), 2);
      expect(jsNumOr0(disp[0]['amount']), 200);
      expect(jsNumOr0(disp[1]['seq']), 1);
      expect(jsNumOr0(disp[1]['amount']), 100);
    });
  });

  group('الواجهة — قسم الديون التوأم', () {
    Future<void> boot(
      WidgetTester tester, {
      required void Function(ProviderContainer) seed,
    }) async {
      final c = container();
      final auth = c.read(authServiceProvider);
      await auth.register('doc@clinic.ly', 'secret12');
      await auth.login('doc@clinic.ly', 'secret12', remember: true);
      c.read(reposProvider).settings.set('app.config', config());
      seed(c);
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
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    Future<void> openDebts(WidgetTester tester) async {
      await tester.tap(find.text('المالية'), warnIfMissed: false);
      await settle(tester);
      await tester.tap(
        find.byKey(const Key('fin-seg-debts')),
        warnIfMissed: false,
      );
      await settle(tester);
    }

    testWidgets('بنية البطاقة: شارات وأعمدة ونسبة السداد وأزرار التواصل', (
      tester,
    ) async {
      await boot(
        tester,
        seed: (c) {
          saveNewRecord(
            c.read(reposProvider),
            config(),
            SaveRecordInput(
              name: 'عبدالصمد بوبكر',
              date: '2026-07-15',
              amount: 550,
              clinic: 'الصفوة',
              service: 'حشو عصب',
              payment: 'كاش',
              isDebt: true,
              firstPay: 400,
              phone: '0919929558',
            ),
          );
        },
      );
      await openDebts(tester);

      // v55 — حبوب الحالة أُزيلت (المسددة تختفي تلقائياً)، والطباعة
      // صارت أيقونة أنيقة بجانب القمع.
      expect(find.text('نشطة (1)'), findsNothing);
      expect(find.textContaining('مسددة'), findsNothing);
      expect(find.byKey(const Key('debt-print')), findsOneWidget);

      final c2 = container();
      final debtId = '${c2.read(reposProvider).debts.getAll().single['id']}';
      c2.dispose();

      // م133 — م110 استبدل البطاقة المطوية بجدولٍ (صف ثابت بلا طيّ/توسيع):
      // الاسم وتحته الخدمة سطر فرعي واحد، وعمود «المتبقي» بالجدول مباشرة؛
      // زر «دفعة» أيقونة بلا نص. الضغط المطول يفتح ورقة خياراتٍ سفلية
      // (_openDebtMenu) فيها كل ما كان بالبطاقة الموسّعة سابقاً.
      expect(find.byKey(Key('debt-name-$debtId')), findsOneWidget);
      expect(find.textContaining('حشو عصب'), findsOneWidget);
      expect(find.text('150'), findsOneWidget); // عمود المتبقي بالجدول
      expect(find.byKey(Key('debt-pay-$debtId')), findsOneWidget);
      // بلا ورقة خياراتٍ بعد: لا ملخص، ولا أزرار تواصل، ولا نسبة سداد.
      expect(find.text('0919929558'), findsNothing);
      expect(find.textContaining('مسدد'), findsNothing);

      // الضغط المطول على صفّ الدين يفتح ورقة الخيارات بكل التفاصيل.
      await tester.ensureVisible(find.byKey(Key('debt-card-$debtId')));
      await tester.pumpAndSettle();
      await tester.longPress(
        find.byKey(Key('debt-card-$debtId')),
        warnIfMissed: false,
      );
      await settle(tester);
      // م133 — الملخص سطرٌ واحد مركّب: الإجمالي/المدفوع/متبقٍ/نسبة السداد
      // معاً (لا نصوصاً مستقلة كالبطاقة القديمة)، ورقم الهاتف الخام غير
      // مرئي بعد م121/م128 (يُستخدم داخل روابط tel:/wa.me: فقط).
      expect(
        find.text('الإجمالي 550 • المدفوع 400 • متبقٍ 150 • 73٪ مسدد'),
        findsOneWidget,
      );
      expect(find.text('0919929558'), findsNothing);
      // أزرار التواصل الآن عناصر ورقةٍ بنصوصها لا مفاتيحها.
      expect(find.text('تذكير واتساب'), findsOneWidget);
      expect(find.text('اتصال'), findsOneWidget);
      expect(find.text('رسالة نصية'), findsOneWidget);
      expect(find.text('الدفعات'), findsOneWidget);

      // إغلاق الورقة بالسحب للخارج (إجراءٌ خارج محتواها) يعيد للجدول.
      await tester.tapAt(const Offset(20, 20));
      await settle(tester);
      expect(
        find.text('الإجمالي 550 • المدفوع 400 • متبقٍ 150 • 73٪ مسدد'),
        findsNothing,
      );
    });

    testWidgets('فلتر العيادة من قائمة القمع وشارته وزر مسحها', (tester) async {
      await boot(
        tester,
        seed: (c) {
          final repos = c.read(reposProvider);
          saveNewRecord(
            repos,
            config(),
            SaveRecordInput(
              name: 'أ',
              date: getCurrentDate(),
              amount: 100,
              clinic: 'الصفوة',
              service: 'حشو عصب',
              payment: 'كاش',
              isDebt: true,
            ),
          );
          saveNewRecord(
            repos,
            config(),
            SaveRecordInput(
              name: 'ب',
              date: getCurrentDate(),
              amount: 200,
              clinic: 'ع2',
              service: 'حشو عصب',
              payment: 'كاش',
              isDebt: true,
            ),
          );
        },
      );
      await openDebts(tester);
      // v55 — بلا حبوب حالة: الدينان النشطان ظاهران مباشرة.
      expect(find.text('أ'), findsWidgets);
      expect(find.text('ب'), findsWidgets);

      // قمع ← تصفية على الصفوة: شارة العيادة تظهر وبطاقة «ب» تختفي.
      await tester.tap(
        find.byKey(const Key('debt-tools')),
        warnIfMissed: false,
      );
      await settle(tester);
      await tester.tap(
        find.byKey(const Key('debt-cf-الصفوة')),
        warnIfMissed: false,
      );
      await settle(tester);
      expect(find.text('العيادة:'), findsOneWidget);
      expect(find.text('أ'), findsWidgets);
      expect(find.text('ب'), findsNothing);

      // مسح الشارة يعيد الجميع.
      await tester.tap(
        find.byKey(const Key('debt-clinic-clear')),
        warnIfMissed: false,
      );
      await settle(tester);
      expect(find.text('العيادة:'), findsNothing);
      expect(find.text('ب'), findsWidgets);
    });

    testWidgets('سجل الدفعات: دفعات مرقمة أحدث أولاً وإلغاء بنقرتين', (
      tester,
    ) async {
      await boot(
        tester,
        seed: (c) {
          final repos = c.read(reposProvider);
          saveNewRecord(
            repos,
            config(),
            SaveRecordInput(
              name: 'هند',
              date: getCurrentDate(),
              amount: 300,
              clinic: 'الصفوة',
              service: 'حشو عصب',
              payment: 'كاش',
              isDebt: true,
            ),
          );
          final debt = repos.debts.getAll().single;
          payDebtInstallment(
            repos,
            config(),
            debt,
            amount: 120,
            date: getCurrentDate(),
            payment: 'كاش',
          );
        },
      );
      await openDebts(tester);
      final c2 = container();
      final debt0 = c2.read(reposProvider).debts.getAll().single;
      final debtId = '${debt0['id']}';
      final instId = '${activeInstallments(debt0).single['id']}';
      c2.dispose();

      // م133 — م110 استبدل زر «الدفعات» بالبطاقة الموسّعة بعنصر «الدفعات»
      // بلا مفتاحٍ داخل ورقة خيارات الدين (تُفتح بالضغط المطول على الصف).
      await tester.ensureVisible(find.byKey(Key('debt-card-$debtId')));
      await tester.pumpAndSettle();
      await tester.longPress(
        find.byKey(Key('debt-card-$debtId')),
        warnIfMissed: false,
      );
      await settle(tester);
      await tester.tap(find.text('الدفعات'), warnIfMissed: false);
      await settle(tester);
      expect(find.textContaining('سجل الدفعات —'), findsOneWidget);
      expect(find.text('معلومات الدين'), findsOneWidget);
      expect(find.text('الدفعات (1)'), findsOneWidget);
      expect(find.text('دفعة 1'), findsOneWidget);
      expect(find.text('غير مسدد'), findsWidgets);

      // النقرة الأولى تسلّح «تأكيد» ولا تحذف.
      await tester.tap(
        find.byKey(Key('pay-cancel-$instId')),
        warnIfMissed: false,
      );
      await settle(tester);
      expect(find.text('تأكيد'), findsOneWidget);
      var chk = container();
      expect(
        jsNumOr0(chk.read(reposProvider).debts.getAll().single['paidAmount']),
        120,
      );
      chk.dispose();

      // النقرة الثانية تنفّذ الإلغاء: المبالغ تعود والقائمة تفرغ.
      await tester.tap(
        find.byKey(Key('pay-cancel-$instId')),
        warnIfMissed: false,
      );
      await settle(tester);
      expect(find.text('لا توجد دفعات مسجلة'), findsOneWidget);
      chk = container();
      addTearDown(chk.dispose);
      final d = chk.read(reposProvider).debts.getAll().single;
      expect(jsNumOr0(d['paidAmount']), 0);
      expect(jsNumOr0(d['remaining']), 300);
      expect(d['status'], 'unpaid');
      expect(
        chk
            .read(reposProvider)
            .records
            .getAll()
            .where((r) => jsTruthy(r['isDebtPayment'])),
        isEmpty,
      );
      await tester.tap(
        find.byKey(const Key('pays-close')),
        warnIfMissed: false,
      );
      await settle(tester);
    });

    testWidgets('المسامحة من الكباب بالتأكيد المزدوج تُقفل الدين', (
      tester,
    ) async {
      await boot(
        tester,
        seed: (c) {
          saveNewRecord(
            c.read(reposProvider),
            config(),
            SaveRecordInput(
              name: 'سعاد',
              date: getCurrentDate(),
              amount: 550,
              clinic: 'الصفوة',
              service: 'حشو عصب',
              payment: 'كاش',
              isDebt: true,
              firstPay: 400,
            ),
          );
        },
      );
      await openDebts(tester);
      final c2 = container();
      final debtId = '${c2.read(reposProvider).debts.getAll().single['id']}';
      c2.dispose();

      // م133 — م110 استبدل قائمة الكباب بورقة خياراتٍ سفلية (_openDebtMenu)
      // تُفتح بالضغط المطول على صفّ الدين؛ عناصرها Text بلا مفاتيح.
      await tester.ensureVisible(find.byKey(Key('debt-card-$debtId')));
      await tester.pumpAndSettle();
      await tester.longPress(
        find.byKey(Key('debt-card-$debtId')),
        warnIfMissed: false,
      );
      await settle(tester);
      expect(find.text('تعديل بيانات الدين'), findsOneWidget);
      expect(find.text('حذف الدين'), findsOneWidget);
      await tester.tap(
        find.text('مسامحة بالمبلغ المتبقي'),
        warnIfMissed: false,
      );
      await settle(tester);
      // نافذة التأكيد المزدوج بعدّادها.
      expect(find.byKey(const Key('dc-countdown')), findsOneWidget);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.tap(
        find.byKey(const Key('dc-confirm')),
        warnIfMissed: false,
      );
      await settle(tester);
      expect(find.textContaining('تم مسامحة المريض'), findsOneWidget);

      final chk = container();
      addTearDown(chk.dispose);
      final d = chk.read(reposProvider).debts.getAll().single;
      expect(jsNumOr0(jsOr(d['totalAmount'], d['total'])), 400);
      expect(jsNumOr0(d['remaining']), 0);
      expect(d['status'], 'paid');
      // v55 — المسدد يختفي تلقائياً من القسم كلياً (صفّه يبقى
      // بالقاعدة تاريخاً كما تحقق أعلاه) — لا بطاقة ولا حبوب حالة.
      expect(find.byKey(Key('debt-card-$debtId')), findsNothing);
      expect(find.byKey(Key('debt-pay-$debtId')), findsNothing);
      expect(find.text('لا توجد ديون'), findsOneWidget);
    });
  });
}
