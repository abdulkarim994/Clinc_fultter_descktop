/// اختبارات جولة الترميم — الدلالات الحرفية للمالية المرمَّمة والإعدادات:
/// حسابات الخزينة (مجاميع العيادة وحصص دفعة التركيبة الثلاث والتجميع
/// بالمريض والفلاتر)، تقرير الأرباح الشهري (تقريب حصة الطبيب لصحيح
/// ومرادفات النقد)، أفعال الديون (قسط تركيبة يقسم مخبراً/ربحاً وينشئ سجل
/// الدفعة بحقوله المجمّدة، المعاينة، تعديل يعيد الاشتقاق وينعكس على
/// التركيبة، حذف تعاقبي)، وواجهات الإعدادات الجديدة (العملة تسري على
/// الخزينة، قالب واتساب، تصدير النسخة الاحتياطية VACUUM INTO).
library;

import 'dart:convert';
import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/core/utils/js_compat.dart';
import 'package:dental_clinic_flutter/features/finance/debt_actions.dart';
import 'package:dental_clinic_flutter/features/finance/profits_logic.dart';
import 'package:dental_clinic_flutter/features/finance/treasury_logic.dart'
    hide JMap;
import 'package:dental_clinic_flutter/features/records/record_saver.dart'
    hide JMap;
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'staff_test_session.dart' show staffAdminSession;

Map<String, Object?> _config() => {
  'centerName': 'مركز الاختبار',
  'currency': 'د.ل',
  'doctorPct': 50,
  'clinicRates': {
    'clinics': {
      'ع1': {
        'treatments': {'حشو': 40},
        'prosthetics': 30,
      },
    },
  },
  'clinics': ['ع1'],
  'services': ['حشو', 'تركيبات'],
  'payments': ['كاش', 'تحويل'],
};

void main() {
  group('منطق الخزينة — الحسابات الحرفية', () {
    final debts = [
      {'id': 'dp', 'type': 'prosthetic', 'prostheticId': 'p2'},
      {
        'id': 'dm',
        'type': 'regular',
        'date': '2026-07-05',
        'status': 'partial',
        'remaining': 150,
        'clinic': 'ع1',
      },
    ];
    final records = [
      // نقدية صافية كاش/تحويل
      {
        'id': 'r1',
        'date': '2026-07-01',
        'amount': 100,
        'payment': 'كاش',
        'clinic': 'ع1',
      },
      {
        'id': 'r2',
        'date': '2026-07-02',
        'amount': 200,
        'payment': 'تحويل',
        'clinic': 'ع1',
      },
      // دفعة دين عادية كاش
      {
        'id': 'r3',
        'date': '2026-07-03',
        'amount': 50,
        'payment': 'كاش',
        'clinic': 'ع1',
        'isDebtPayment': true,
        'debtId': 'dm',
      },
      // دفعة دين تركيبة بحقول مجمّدة
      {
        'id': 'r4',
        'date': '2026-07-04',
        'amount': 250,
        'payment': 'كاش',
        'clinic': 'ع1',
        'name': 'نوري',
        'isDebtPayment': true,
        'debtId': 'dp',
        '_fullAmount': 250,
        '_labAmount': 100,
        '_docAmount': 45,
      },
    ];
    final pros = [
      {
        'id': 'p1',
        'date': '2026-07-06',
        'clinic': 'ع1',
        'name': 'مريم',
        'total': 500,
        'labValue': 200,
        'doctorShare': 90,
        'clinicShare': 210,
        'payment': 'كاش',
      },
      {
        'id': 'p2',
        'date': '2026-07-07',
        'clinic': 'ع1',
        'name': 'نوري',
        'total': 600,
        'labValue': 300,
        'isDebt': true,
        'payment': 'دين',
      },
    ];

    TreasurySlice slice() => TreasurySlice(
      '2026-07',
      records: [for (final r in records) Map<String, Object?>.from(r)],
      prosthetics: [for (final p in pros) Map<String, Object?>.from(p)],
      debts: [for (final d in debts) Map<String, Object?>.from(d)],
    );

    test('مجاميع العيادة والإجماليات العليا', () {
      final s = slice();
      expect(clinicCash(s, 'ع1'), 150); // 100 + دفعة عادية 50
      expect(clinicXfer(s, 'ع1'), 200);
      // المدفوع للتركيبات = غير الدين 500 + دفعة الدين 250.
      expect(clinicProsTotalPaid(s, 'ع1'), 750);
      // حصة طبيب التركيبات = 90 + _docAmount 45.
      expect(clinicProsDoc(s, 'ع1'), 135);
      expect(clinicDebtRemaining(s, 'ع1'), 150);
      final t = treasuryTotals(s);
      // م111 — المحصّل صار كل المقبوض: كاش + تحويل + كامل مدفوع التركيبات.
      expect(t.grand, 150 + 200 + 750);
      expect(t.debtRem, 150);
    });

    test('حصص دفعة التركيبة الثلاث — الحقول المجمّدة وإلا الاشتقاق', () {
      final frozen = Map<String, Object?>.from(records[3]);
      expect(prosPayLab(frozen, 50), 100);
      expect(prosPayDoc(frozen, 50), 45);
      // العيادة = المتبقي بالبناء: 250 − 100 − 45 = 105.
      expect(prosPayClin(frozen, 50), 105);

      // سجل قديم بلا أي حقل مجمّد: دلالة الأصل الحرفية — doc=0 يجعل
      // فرع المخبر يستهلك كامل الدفعة (lab=full) فطبيب وعيادة صفر.
      final legacyBare = <String, Object?>{'amount': 200, '_fullAmount': 200};
      expect(prosPayLab(legacyBare, 50), 200);
      expect(prosPayDoc(legacyBare, 50), 0);
      expect(prosPayClin(legacyBare, 50), 0);
      // قديم بحقل _docAmount فقط: المخبر بالاشتقاق ثم الطبيب المجمّد.
      final legacyDoc = <String, Object?>{
        'amount': 200,
        '_fullAmount': 200,
        '_docAmount': 50,
      };
      expect(prosPayLab(legacyDoc, 50), 100); // 200 − 50×100/50
      expect(prosPayDoc(legacyDoc, 50), 50);
      expect(prosPayClin(legacyDoc, 50), 50);
    });

    test('تجميع التركيبات بالمريض ودفعات الأشهر الأخرى والفلاتر', () {
      final s = slice();
      final groups = prosGrouped(s, 'ع1', 50);
      expect(groups, hasLength(2));
      final byName = {for (final g in groups) g.name: g};
      expect(byName['مريم']!.docTotal, 90);
      expect(byName['نوري']!.total, 600); // التركيبة الدين بمجموعها
      expect(byName['نوري']!.docTotal, 45); // من الدفعة فقط

      // دفعة خارج الشهر تظهر في «أشهر أخرى».
      final crossRecords = [
        ...records,
        {
          'id': 'r5',
          'date': '2026-06-15',
          'amount': 100,
          'isDebtPayment': true,
          'debtId': 'dp',
          'clinic': 'ع1',
        },
      ];
      final cross = crossMonthPayments(
        byName['نوري']!,
        [for (final r in crossRecords) Map<String, Object?>.from(r)],
        [for (final d in debts) Map<String, Object?>.from(d)],
        '2026-07',
      );
      expect(cross, hasLength(1));
      expect(cross.single['id'], 'r5');

      // فلاتر التفصيل: بحث اسم + نطاق تاريخ + فرز اسم تصاعدي.
      final items = filteredDetailItems(
        s,
        'cash',
        'ع1',
        from: '2026-07-02',
        sort: 'name-asc',
      );
      expect(items, hasLength(1)); // r3 فقط (r1 قبل النطاق وr4 تركيبات)
      expect(items.single['id'], 'r3');
    });
  });

  group('تقرير الأرباح الشهري — getMonthlyReport حرفياً', () {
    test('تقريب حصة الطبيب لصحيح ومرادفات النقد والإجماليات', () {
      final records = [
        {
          'id': '1', 'date': '2026-07-01', 'amount': 105,
          'payment': 'نقد', // مرادف كاش
          '_rateSnapshot': {'doctorPct': 33},
        },
        {'id': '2', 'date': '2026-07-02', 'amount': 200, 'payment': 'بطاقة'},
      ];
      final pros = [
        {
          'id': 'p1',
          'date': '2026-07-03',
          'total': 400,
          'labValue': 100,
          'doctorShare': 90,
          'clinicShare': 210,
          'payment': 'كاش',
        },
      ];
      final rep = getMonthlyReport(
        [for (final r in records) Map<String, Object?>.from(r)],
        [for (final p in pros) Map<String, Object?>.from(p)],
        const [],
        '2026-07',
        50,
      );
      expect(rep.recCash, 105);
      expect(rep.recXfer, 200);
      // طبيب السجلات = round(105×0.33 + 200×0.5) = round(134.65) = 135.
      expect(rep.recDoctor, 135);
      expect(rep.recClinic, 305 - 135);
      expect(rep.prosProfit, 300);
      expect(rep.doctorTotal, 135 + 90);
      expect(rep.grandTotal, 305 + 400);
    });

    test('م112: الأرباح بأساس القبض — الدين لا يدخل حتى يُدفع وبشهر دفعه', () {
      Map<String, Object?> cp(Map<String, Object?> m) =>
          Map<String, Object?>.from(m);
      final pros = <Map<String, Object?>>[
        {
          'id': 'P',
          'date': '2026-07-10',
          'total': 400,
          'labValue': 0,
          'isDebt': 1,
          'clinicShare': 0,
        },
      ];
      final debts = <Map<String, Object?>>[
        {'id': 'D', 'prostheticId': 'P', 'type': 'prosthetic'},
      ];
      final records = <Map<String, Object?>>[
        // دفعة دين التركيبة قُبضت في أغسطس.
        {
          'id': 'R',
          'date': '2026-08-05',
          'amount': 250,
          '_fullAmount': 250,
          '_labAmount': 0,
          '_docAmount': 100,
          'isDebtPayment': 1,
          'debtId': 'D',
          'payment': 'كاش',
        },
      ];
      // يوليو: تركيبة دَين بلا أي قبض ⇒ لا إيراد (كانت 400 «وهمية»).
      final july = getMonthlyReport(
        const [],
        [for (final p in pros) cp(p)],
        [for (final d in debts) cp(d)],
        '2026-07',
        50,
      );
      expect(july.prosRevenue, 0);
      expect(july.grandTotal, 0);
      // أغسطس: الدفعة 250 قُبضت فيه ⇒ تدخل إيراد أغسطس.
      final aug = getMonthlyReport(
        [for (final r in records) cp(r)],
        [for (final p in pros) cp(p)],
        [for (final d in debts) cp(d)],
        '2026-08',
        50,
      );
      expect(aug.prosRevenue, 250);
      expect(aug.grandTotal, 250);
    });

    test('صفوف العيادات مرتبة بالإيراد والسنة تجمع الأشهر', () {
      final records = [
        {
          'id': '1',
          'date': '2026-07-01',
          'amount': 100,
          'payment': 'كاش',
          'clinic': 'أ',
        },
        {
          'id': '2',
          'date': '2026-07-02',
          'amount': 300,
          'payment': 'كاش',
          'clinic': 'ب',
        },
        {
          'id': '3',
          'date': '2026-03-05',
          'amount': 50,
          'payment': 'تحويل',
          'clinic': 'أ',
        },
      ];
      final rows = monthlyClinicRows(
        '2026-07',
        records: [for (final r in records) Map<String, Object?>.from(r)],
        prosthetics: const [],
        debts: const [],
        clinics: const ['أ', 'ب'],
        doctorPct: 50,
      );
      expect(rows.first.name, 'ب'); // الأعلى إيراداً أولاً
      expect(rows.first.revenue, 300);

      final y = yearTotals(
        '2026',
        records: [for (final r in records) Map<String, Object?>.from(r)],
        prosthetics: const [],
        debts: const [],
      );
      expect(y.cash, 400);
      expect(y.xfer, 50);
      expect(y.grand, 450);
      expect(
        monthGrandFor(
          '2026-03',
          records: [for (final r in records) Map<String, Object?>.from(r)],
          prosthetics: const [],
          debts: const [],
        ),
        50,
      );
    });
  });

  group('أفعال الديون — النقل الحرفي', () {
    late Directory tmp;
    late ProviderContainer c;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('m6r_');
      c = ProviderContainer(
        overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
        ],
      );
      c.read(reposProvider).settings.set('app.config', _config());
    });
    tearDown(() {
      c.dispose();
      tmp.deleteSync(recursive: true);
    });

    test('قسط تركيبة: مخبر أولاً ثم ربح بنسبة العيادة + سجل دفعة مجمّد', () {
      final repos = c.read(reposProvider);
      // تركيبة دين 600/مخبر 300 بدفعة أولى 100 (كلها للمخبر).
      final r = saveNewRecord(
        repos,
        _config(),
        const SaveRecordInput(
          name: 'نوري',
          date: '2026-07-10',
          amount: 600,
          clinic: 'ع1',
          service: 'تركيبات',
          payment: 'كاش',
          labValue: 300,
          isDebt: true,
          firstPay: 100,
        ),
      );
      var debt = repos.debts.getById(r.debtId!)!;
      expect(jsNumOr0(debt['labPaid']), 100);

      // معاينة قسط 300: متبقي المخبر 200 ← مخبر، 100 ربح بنسبة 30٪.
      final pv = previewInstallment(_config(), debt, 300);
      expect(pv.toLab, 200);
      expect(pv.toProfit, 100);
      expect(pv.docShare, 30);
      expect(pv.clinShare, 70);

      // تسجيل القسط: الدين يتقدم وينشأ سجل «دفعة تركيبات — …» بحقوله.
      final result = payDebtInstallment(
        repos,
        _config(),
        debt,
        amount: 300,
        date: '2026-07-15',
        payment: 'تحويل',
      );
      expect(result.isFull, isFalse);
      debt = repos.debts.getById(r.debtId!)!;
      expect(jsNumOr0(debt['paidAmount']), 400);
      expect(jsNumOr0(debt['remaining']), 200);
      expect(jsNumOr0(debt['labPaid']), 300);
      expect(jsNumOr0(debt['doctorEarned']), 30);
      expect(debt['status'], 'partial');
      expect((debt['installments'] as List), hasLength(2));

      final pay = repos.records.getById(result.payRecordId)!;
      expect('${pay['service']}', startsWith('دفعة تركيبات —'));
      expect(jsNumOr0(pay['_labAmount']), 200);
      expect(jsNumOr0(pay['_docAmount']), 30);
      expect(pay['payment'], 'تحويل');
      expect(pay['date'], '2026-07-15');
      expect(jsNumOr0(pay['isDebtPayment']), 1);

      // رسائل التحقق: أكبر من المتبقي.
      expect(
        () => payDebtInstallment(
          repos,
          _config(),
          debt,
          amount: 999,
          date: '2026-07-16',
          payment: 'كاش',
        ),
        throwsA(predicate((e) => '$e'.contains('أكبر من المتبقي'))),
      );
    });

    test('تعديل الإجمالي ينعكس على التركيبة بحصص لقطتها وعلى الحالة', () {
      final repos = c.read(reposProvider);
      final r = saveNewRecord(
        repos,
        _config(),
        const SaveRecordInput(
          name: 'مريم',
          date: '2026-07-10',
          amount: 500,
          clinic: 'ع1',
          service: 'تركيبات',
          payment: 'كاش',
          labValue: 200,
          isDebt: true,
          firstPay: 100,
        ),
      );
      editDebt(
        repos,
        _config(),
        r.debtId!,
        name: 'مريم الجديدة',
        phone: '0911',
        notes: 'ملاحظة',
        total: 700,
      );
      final d = repos.debts.getById(r.debtId!)!;
      expect(d['name'], 'مريم الجديدة');
      expect(jsNumOr0(d['remaining']), 600);
      expect(d['status'], 'partial');
      // التركيبة: total 700 وحصصها من صافي 500 بنسبة اللقطة 30٪.
      final p = repos.prosthetics.getById(r.entryId)!;
      expect(jsNumOr0(p['total']), 700);
      expect(jsNumOr0(p['doctorShare']), 150); // (700−200)×30٪
      expect(jsNumOr0(p['clinicShare']), 350);
      expect(p['name'], 'مريم الجديدة');
    });

    test('الحذف التعاقبي: شواهد للدفعات والتركيبة والدين', () {
      final repos = c.read(reposProvider);
      final r = saveNewRecord(
        repos,
        _config(),
        const SaveRecordInput(
          name: 'سعاد',
          date: '2026-07-10',
          amount: 600,
          clinic: 'ع1',
          service: 'تركيبات',
          payment: 'كاش',
          labValue: 300,
          isDebt: true,
          firstPay: 100,
        ),
      );
      payDebtInstallment(
        repos,
        _config(),
        repos.debts.getById(r.debtId!)!,
        amount: 100,
        date: '2026-07-11',
        payment: 'كاش',
      );
      expect(repos.records.getAll(), hasLength(2)); // دفعتان
      final deleted = deleteDebtCascade(repos, r.debtId!);
      expect(deleted, 4); // دفعتان + تركيبة + دين
      expect(repos.debts.getAll(), isEmpty);
      expect(repos.records.getAll(), isEmpty);
      expect(repos.prosthetics.getAll(), isEmpty);
      // شواهد لا حذفاً فيزيائياً (تتزامن).
      final raw = c
          .read(localDbProvider)
          .queryFirst('SELECT COUNT(*) c FROM debts WHERE _deleted = 1')!;
      expect(raw['c'], 1);
    });
  });

  group('الواجهة — الإعدادات المرمَّمة', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('m6rw_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    Future<void> boot(
      WidgetTester tester, {
      void Function(ProviderContainer c)? seed,
    }) async {
      final c = ProviderContainer(
        overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
        ],
      );
      final auth = c.read(authServiceProvider);
      await auth.register('doc@clinic.ly', 'secret12');
      await auth.login('doc@clinic.ly', 'secret12', remember: true);
      c.read(reposProvider).settings.set('app.config', _config());
      seed?.call(c);
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
      // م36 — الافتراضي صار «الرئيسية»: اختبارات هذا الملف تبدأ من السجلات.
      await tester.tap(find.text('السجلات'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    Finder vScrollable() => find
        .byWidgetPredicate(
          (w) =>
              w is Scrollable &&
              axisDirectionToAxis(w.axisDirection) == Axis.vertical,
        )
        .first;

    testWidgets('تغيير العملة يسري على الخزينة فوراً', (tester) async {
      await boot(
        tester,
        seed: (c) {
          saveNewRecord(
            c.read(reposProvider),
            _config(),
            SaveRecordInput(
              name: 'أ',
              date: getCurrentDate(),
              amount: 100,
              clinic: 'ع1',
              service: 'حشو',
              payment: 'كاش',
            ),
          );
        },
      );
      await tester.tap(find.byTooltip('الإعدادات'));
      await settle(tester);
      await tester.tap(
        find.byKey(const Key('group-center')),
        warnIfMissed: false,
      );
      await settle(tester);
      await tester.scrollUntilVisible(
        find.byKey(const Key('currency-input')),
        200,
        scrollable: vScrollable(),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('currency-input')), 'د.ت');
      await tester.ensureVisible(find.byKey(const Key('currency-save')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('currency-save')),
        warnIfMissed: false,
      );
      await settle(tester);
      // م92 — رجوعان: صفحة القسم ثم شاشة الإعدادات.
      await tester.tap(
        find.byKey(const Key('settings-section-back')),
        warnIfMissed: false,
      );
      await settle(tester);
      await tester.tap(find.byType(BackButton).first, warnIfMissed: false);
      await settle(tester);
      await tester.tap(find.text('المالية'), warnIfMissed: false);
      await settle(tester);
      // م133 — «المالية» صارت قائمة بطاقات أقسام (خزينة/ديون/أرباح/كشف
      // حساب، م108) بلا أي مبلغٍ معروض على مستوى القائمة نفسها (فقط
      // عنوان/عنوان فرعي/أيقونة لكل بطاقة، finance_screen.dart)؛ الدخل
      // الفعلي بالعملة يظهر داخل قسم «الخزينة» فعلاً — فيلزم الدخول له
      // أولاً (نفس نمط m13/m4b). البطاقة تفتح MaterialPageRoute حقيقياً
      // فتحتاج pumpAndSettle لإنهاء حركة الانتقال (نفس ما وُجد في
      // m89/m90/m98/m13).
      await tester.tap(
        find.byKey(const Key('fin-seg-treasury')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      // الدخل الفعلي بالعملة الجديدة.
      expect(find.textContaining('د.ت'), findsWidgets);
    });

    testWidgets('قالب واتساب يُحفظ في config ويُملأ في حوار الملف', (
      tester,
    ) async {
      await boot(
        tester,
        seed: (c) {
          saveNewRecord(
            c.read(reposProvider),
            _config(),
            SaveRecordInput(
              name: 'هدى',
              date: getCurrentDate(),
              amount: 100,
              clinic: 'ع1',
              service: 'حشو',
              payment: 'كاش',
              phone: '0911111111',
            ),
          );
        },
      );
      await tester.tap(find.byTooltip('الإعدادات'));
      await settle(tester);
      await tester.scrollUntilVisible(
        find.byKey(const Key('group-wa')),
        300,
        scrollable: vScrollable(),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('group-wa')), warnIfMissed: false);
      await settle(tester);
      await tester.ensureVisible(find.byKey(const Key('add-watpl')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add-watpl')), warnIfMissed: false);
      await settle(tester);
      await tester.ensureVisible(find.byKey(const Key('watpl-lbl-0')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('watpl-lbl-0')), 'تذكير');
      await tester.enterText(
        find.byKey(const Key('watpl-msg-0')),
        'مرحباً {name} من {center}',
      );
      await tester.ensureVisible(find.byKey(const Key('save-watpls')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('save-watpls')),
        warnIfMissed: false,
      );
      await settle(tester);
      expect(find.text('تذكير'), findsOneWidget);

      final chk = ProviderContainer(
        overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
        ],
      );
      final cfg = Map<String, Object?>.from(
        chk.read(reposProvider).settings.get('app.config') as Map,
      );
      chk.dispose();
      expect((cfg['waTemplates'] as List), hasLength(1));

      // حوار القوالب في الملف يعرض النص مملوءاً بالاسم والمركز.
      // م92 — رجوعان: صفحة القسم ثم شاشة الإعدادات.
      await tester.tap(
        find.byKey(const Key('settings-section-back')),
        warnIfMissed: false,
      );
      await settle(tester);
      await tester.tap(find.byType(BackButton).first, warnIfMissed: false);
      await settle(tester);
      await tester.enterText(find.byKey(const Key('patient-search')), 'هدى');
      await settle(tester);
      await tester.tap(
        find.byKey(const Key('patient-card-هدى')),
        warnIfMissed: false,
      );
      await settle(tester);
      await tester.tap(
        find.byKey(const Key('pp-actions')),
        warnIfMissed: false,
      );
      await settle(tester);
      await tester.tap(find.byKey(const Key('pp-act-wa')), warnIfMissed: false);
      await settle(tester);
      expect(find.text('مرحباً هدى من مركز الاختبار'), findsOneWidget);
    });

    testWidgets('تصدير النسخة الاحتياطية ينتج قاعدة صالحة في exports', (
      tester,
    ) async {
      await boot(
        tester,
        seed: (c) {
          saveNewRecord(
            c.read(reposProvider),
            _config(),
            SaveRecordInput(
              name: 'أ',
              date: getCurrentDate(),
              amount: 100,
              clinic: 'ع1',
              service: 'حشو',
              payment: 'كاش',
            ),
          );
        },
      );
      await tester.tap(find.byTooltip('الإعدادات'));
      await settle(tester);
      await tester.scrollUntilVisible(
        find.byKey(const Key('group-storage')),
        300,
        scrollable: vScrollable(),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('group-storage')),
        warnIfMissed: false,
      );
      await settle(tester);
      await tester.ensureVisible(find.byKey(const Key('export-json')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('export-json')),
        warnIfMissed: false,
      );
      await settle(tester);
      // تصريف Snackbar التصدير ثم تثبيت الزر الثاني قبل نقره.
      await tester.pump(const Duration(seconds: 5));
      await tester.ensureVisible(find.byKey(const Key('export-excel')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('export-excel')),
        warnIfMissed: false,
      );
      await settle(tester);

      // JSON بنفس مفاتيح الأصل وبياناته.
      final jsonFiles = Directory('${tmp.path}/exports')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList();
      expect(jsonFiles, hasLength(1));
      final data = jsonDecode(jsonFiles.single.readAsStringSync()) as Map;
      expect((data['records'] as List), hasLength(1));
      expect((data['config'] as Map)['centerName'], 'مركز الاختبار');
      expect(data.containsKey('exportDate'), isTrue);

      // Excel: ملف xlsx حقيقي (zip يبدأ بتوقيع PK).
      final xlsxFiles = Directory('${tmp.path}/exports')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.xlsx'))
          .toList();
      expect(xlsxFiles, hasLength(1));
      final head = xlsxFiles.single.openSync().readSync(2);
      expect(String.fromCharCodes(head), 'PK');
    });
  });
}
