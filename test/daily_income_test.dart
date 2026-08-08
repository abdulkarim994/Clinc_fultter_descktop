/// اختبار بناء صفوف «دخل اليوم» (منطق نقيّ بلا قاعدة): علاجات نقدية/دَين +
/// دفعات ديون، مع القيمة/المدفوع/المتبقي من الدين المرتبط، والترتيب بالساعة.
library;

import 'package:dental_clinic_flutter/core/utils/js_compat.dart'
    show getCurrentDate;
import 'package:dental_clinic_flutter/features/records/home_logic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final today = getCurrentDate();

  test('صفوف اليوم: نقد + دين + دفعة دين، بالقيم الصحيحة وترتيب الساعة', () {
    final records = <Map<String, Object?>>[
      {
        'name': 'أ',
        'date': today,
        'service': 'حشو',
        'payment': 'كاش',
        'amount': 100,
        'createdAt': 1000,
      },
      {
        // الشكل الحقيقي للحفظ: السجل لا يحمل debtId — الدين هو من يشير
        // إليه عبر recordId (انظر record_saver.dart، بلاغ ما بعد 92).
        'id': 'rb',
        'name': 'ب',
        'date': today,
        'service': 'تركيب',
        'payment': 'دين',
        'isDebt': 1,
        'amount': 600,
        'createdAt': 2000,
      },
      {
        'name': 'ج',
        'date': today,
        'service': 'سداد',
        'isDebtPayment': 1,
        'debtId': 'd2',
        'payment': 'كاش',
        'amount': 50,
        'createdAt': 3000,
      },
      // يوم آخر — يجب ألا يظهر.
      {'name': 'قديم', 'date': '2000-01-01', 'payment': 'كاش', 'amount': 999},
    ];
    final debts = <Map<String, Object?>>[
      {
        'id': 'd1',
        'recordId': 'rb',
        'payment': 'تحويل',
        'total_amount': 600,
        'paid_amount': 200,
        'remaining': 400,
      },
      {'id': 'd2', 'remaining': 150},
    ];

    final rows = todayLedgerRows(records, const [], debts);
    expect(rows.length, 3);

    expect(rows[0].name, 'أ');
    expect(rows[0].value, 100);
    expect(rows[0].paid, 100);
    expect(rows[0].remaining, 0);

    expect(rows[1].name, 'ب');
    // دُفع جزء (200) ⇒ تظهر طريقة الدفع الحقيقية من صف الدين لا كلمة «دين».
    expect(rows[1].payment, 'تحويل');
    expect(rows[1].value, 600);
    expect(rows[1].paid, 200);
    expect(rows[1].remaining, 400);

    expect(rows[2].name, 'ج');
    expect(rows[2].payment, 'دفعة دين');
    // م130 — المستحق لحظة الدفعة: متبقٍ 150 + دفعة 50 = 200.
    expect(rows[2].value, 200);
    expect(rows[2].paid, 50);
    expect(rows[2].remaining, 150);

    final t = ledgerTotals(rows);
    expect(t.count, 3);
    expect(t.value, 900);
    expect(t.paid, 350);
    expect(t.remaining, 550);
  });

  test('ledgerTimeLabel يصوغ HH:MM و— عند غياب الوقت', () {
    expect(ledgerTimeLabel(0), '—');
    final ms = DateTime(2026, 8, 3, 9, 5).millisecondsSinceEpoch;
    expect(ledgerTimeLabel(ms), '09:05');
  });

  test('الفلترة والفرز', () {
    const rows = [
      LedgerRow(
          name: 'أ',
          clinic: 'ع1',
          service: '',
          payment: 'كاش',
          timeMs: 1,
          value: 100,
          paid: 100,
          remaining: 0),
      LedgerRow(
          name: 'ب',
          clinic: 'ع2',
          service: '',
          payment: 'دين',
          timeMs: 2,
          value: 600,
          paid: 200,
          remaining: 400),
      LedgerRow(
          name: 'ج',
          clinic: 'ع1',
          service: '',
          payment: 'تحويل',
          timeMs: 3,
          value: 50,
          paid: 50,
          remaining: 0),
    ];
    expect(filterLedgerRows(rows, nameQuery: 'ب').length, 1);
    expect(filterLedgerRows(rows, clinics: {'ع1'}).length, 2);
    expect(filterLedgerRows(rows, payments: {'دين'}).length, 1);
    expect(filterLedgerRows(rows, onlyRemaining: true).map((r) => r.name).toList(),
        ['ب']);
    // اختيار متعدد لطرق الدفع.
    expect(filterLedgerRows(rows, payments: {'كاش', 'تحويل'}).length, 2);

    expect(sortLedgerRows(rows, LedgerSort.valueDesc).map((r) => r.name).toList(),
        ['ب', 'أ', 'ج']);
    expect(sortLedgerRows(rows, LedgerSort.nameDesc).first.name, 'ج');
    expect(sortLedgerRows(rows, LedgerSort.timeDesc).first.name, 'ج');
  });

  test('التقسيم الصباحي/المسائي (فاصل 12)', () {
    final morning = DateTime(2026, 8, 3, 9, 0).millisecondsSinceEpoch;
    final evening = DateTime(2026, 8, 3, 15, 0).millisecondsSinceEpoch;
    expect(ledgerPeriodOf(morning), LedgerPeriod.morning);
    expect(ledgerPeriodOf(evening), LedgerPeriod.evening);
    expect(ledgerPeriodOf(0), LedgerPeriod.morning);
    final rows = [
      LedgerRow(
          name: 'ص',
          clinic: '',
          service: '',
          payment: 'كاش',
          timeMs: morning,
          value: 100,
          paid: 100,
          remaining: 0),
      LedgerRow(
          name: 'م',
          clinic: '',
          service: '',
          payment: 'كاش',
          timeMs: evening,
          value: 200,
          paid: 200,
          remaining: 0),
    ];
    expect(
        filterLedgerRows(rows, period: LedgerPeriod.morning)
            .map((r) => r.name)
            .toList(),
        ['ص']);
    expect(
        filterLedgerRows(rows, period: LedgerPeriod.evening)
            .map((r) => r.name)
            .toList(),
        ['م']);
  });

  test('إجماليات مع مصروفات: صافي الدخل = المدفوع − المصروفات', () {
    const rows = [
      LedgerRow(
          name: 'أ',
          clinic: '',
          service: '',
          payment: 'كاش',
          timeMs: 1,
          value: 300,
          paid: 300,
          remaining: 0),
      LedgerRow(
          name: 'ب',
          clinic: '',
          service: '',
          payment: 'دين',
          method: 'تحويل', // الدفعة الجزئية كانت تحويلاً
          timeMs: 2,
          value: 600,
          paid: 200,
          remaining: 400),
      LedgerRow(
          isExpense: true,
          name: 'كلور',
          clinic: '—',
          service: 'تنظيف',
          payment: 'مصروف',
          method: 'كاش',
          timeMs: 3,
          value: 120,
          paid: 0,
          remaining: 0),
    ];
    final t = ledgerTotals(rows);
    expect(t.count, 2); // صفّا الدخل فقط (المصروف لا يُعدّ حالة)
    expect(t.value, 900);
    expect(t.paid, 500);
    expect(t.remaining, 400);
    expect(t.expense, 120);
    expect(t.net, 380); // 500 − 120
  });

  test('م95: توزيع البطاقة حسب الطريقة الفعلية — مدفوع/مصروف/صافي', () {
    const rows = [
      // علاج كاش عادي.
      LedgerRow(
          name: 'أ',
          clinic: '',
          service: '',
          payment: 'كاش',
          timeMs: 1,
          value: 300,
          paid: 300,
          remaining: 0),
      // دين مدموج بدفعة أولى تحويل (التسمية تعرض تحويل والطريقة تحويل).
      LedgerRow(
          name: 'ب',
          clinic: '',
          service: '',
          payment: 'تحويل',
          method: 'تحويل',
          timeMs: 2,
          value: 600,
          paid: 200,
          remaining: 400),
      // دفعة دين قديمة كاش: التسمية «دفعة دين» والطريقة الفعلية كاش.
      LedgerRow(
          name: 'ج',
          clinic: '',
          service: '',
          payment: 'دفعة دين',
          method: 'كاش',
          timeMs: 3,
          value: 70,
          paid: 70,
          remaining: 130),
      // دين بلا دفعة: لا يضيف شيئاً للتوزيع.
      LedgerRow(
          name: 'د',
          clinic: '',
          service: '',
          payment: 'دين',
          method: 'كاش',
          timeMs: 4,
          value: 500,
          paid: 0,
          remaining: 500),
      // مصروفان: كاش وتحويل.
      LedgerRow(
          isExpense: true,
          name: 'كلور',
          clinic: '—',
          service: 'تنظيف',
          payment: 'مصروف',
          method: 'كاش',
          timeMs: 5,
          value: 120,
          paid: 0,
          remaining: 0),
      LedgerRow(
          isExpense: true,
          name: 'قفازات',
          clinic: '—',
          service: 'مواد',
          payment: 'مصروف',
          method: 'تحويل',
          timeMs: 6,
          value: 50,
          paid: 0,
          remaining: 0),
    ];
    final t = ledgerTotals(rows);
    // المدفوع: 300 كاش + 200 تحويل + 70 كاش (دفعة دين) = 570.
    expect(t.paid, 570);
    expect(t.paidBy['كاش'], 370);
    expect(t.paidBy['تحويل'], 200);
    // المصروف: 120 كاش + 50 تحويل = 170.
    expect(t.expense, 170);
    expect(t.expenseBy['كاش'], 120);
    expect(t.expenseBy['تحويل'], 50);
    // الصافي: إجمالي 400، كاش 250، تحويل 150.
    expect(t.net, 400);
    expect(t.netOf('كاش'), 250);
    expect(t.netOf('تحويل'), 150);
    // الدين المتبقي كما هو.
    expect(t.remaining, 1030);
  });

  test('م95: الطريقة الفعلية تُبنى من الصفوف الحقيقية (دمج + دفعة قديمة)', () {
    final today = getCurrentDate();
    final records = <Map<String, Object?>>[
      // دين اليوم بدفعة أولى تحويل — الطريقة الفعلية من صف الدين.
      {
        'id': 'R1',
        'name': 'ماجد',
        'date': today,
        'payment': 'دين',
        'isDebt': 1,
        'amount': 400,
        'createdAt': 1000,
      },
      {
        'name': 'ماجد',
        'date': today,
        'isDebtPayment': 1,
        'debtId': 'D',
        'payment': 'تحويل',
        'amount': 100,
        'createdAt': 1001,
      },
      // دفعة كاش على دين قديم — التسمية «دفعة دين» والطريقة كاش.
      {
        'name': 'سالم',
        'date': today,
        'isDebtPayment': 1,
        'debtId': 'OLD',
        'payment': 'كاش',
        'amount': 70,
        'createdAt': 2000,
      },
    ];
    final debts = <Map<String, Object?>>[
      {
        'id': 'D',
        'date': today,
        'recordId': 'R1',
        'payment': 'تحويل',
        'total_amount': 400,
        'paid_amount': 100,
        'remaining': 300,
      },
      {
        'id': 'OLD',
        'date': '2020-01-01',
        'total_amount': 500,
        'paid_amount': 430,
        'remaining': 70,
      },
    ];
    final rows = todayLedgerRows(records, const [], debts);
    expect(rows.length, 2);
    final t = ledgerTotals(rows);
    expect(t.paidBy['تحويل'], 100); // دفعة الدين المدموج
    expect(t.paidBy['كاش'], 70); // دفعة الدين القديم
    expect(t.paid, 170);
  });

  test('م101: دفعة بتاريخ آخر لا تزدوج — صف الدين يجمع أقساط اليوم فقط', () {
    final today = getCurrentDate();
    final records = <Map<String, Object?>>[
      {
        'id': 'R1',
        'name': 'ماجد',
        'date': today,
        'payment': 'دين',
        'isDebt': 1,
        'amount': 400,
        'createdAt': 1000,
      },
      // دفعة مؤرخة بيوم آخر (متقدم): لا تظهر اليوم ولا تدخل مدفوع الصف.
      {
        'name': 'ماجد',
        'date': '2030-01-01',
        'isDebtPayment': 1,
        'debtId': 'D',
        'payment': 'كاش',
        'amount': 150,
        'createdAt': 1002,
      },
    ];
    final debts = <Map<String, Object?>>[
      {
        'id': 'D',
        'date': today,
        'recordId': 'R1',
        'payment': 'كاش',
        'total_amount': 400,
        'paid_amount': 250, // تراكمي: 100 اليوم + 150 يوم آخر
        'remaining': 150,
        'installments': [
          {'id': 'i1', 'amount': 100, 'date': today, 'payment': 'كاش'},
          {'id': 'i2', 'amount': 150, 'date': '2030-01-01', 'payment': 'كاش'},
        ],
      },
    ];
    final rows = todayLedgerRows(records, const [], debts);
    expect(rows.length, 1);
    expect(rows.first.paid, 100); // أقساط اليوم فقط — لا 250 التراكمي
    expect(ledgerTotals(rows).paid, 100);
  });

  test('م101: يوم الاحتساب incomeDate يحكم الظهور في جدول اليوم', () {
    final today = getCurrentDate();
    final records = <Map<String, Object?>>[
      // سجل مؤرخ بالأمس لكنه يُحسب اليوم: يظهر اليوم.
      {
        'id': 'RA',
        'name': 'أ',
        'date': '2020-01-01',
        'incomeDate': today,
        'payment': 'كاش',
        'amount': 200,
        'createdAt': 1000,
      },
      // سجل مؤرخ بالأمس بلا يوم احتساب: لا يظهر اليوم.
      {
        'id': 'RB',
        'name': 'ب',
        'date': '2020-01-01',
        'payment': 'كاش',
        'amount': 300,
        'createdAt': 1001,
      },
      // دفعة دين قديمة مؤرخة بالأمس تُحسب اليوم: تظهر اليوم «دفعة دين».
      {
        'id': 'RC',
        'name': 'ج',
        'date': '2020-01-01',
        'incomeDate': today,
        'isDebtPayment': 1,
        'debtId': 'OLD',
        'payment': 'كاش',
        'amount': 70,
        'createdAt': 1002,
      },
    ];
    final rows = todayLedgerRows(records, const [], [
      {'id': 'OLD', 'date': '2019-01-01', 'remaining': 30},
    ]);
    expect(rows.length, 2);
    expect(rows[0].name, 'أ');
    expect(rows[0].paid, 200);
    expect(rows[1].name, 'ج');
    expect(rows[1].payment, 'دفعة دين');
    expect(ledgerTotals(rows).paid, 270);
  });

  test('م105: قيمة none — في السجلات والمالية فقط، خارج كل جداول الدخل', () {
    final today = getCurrentDate();
    final records = <Map<String, Object?>>[
      // سجل مؤرخ اليوم لكن يوم احتسابه none: لا يظهر حتى في جدول اليوم.
      {
        'id': 'RN',
        'name': 'ن',
        'date': today,
        'incomeDate': kNoIncomeDay,
        'payment': 'كاش',
        'amount': 900,
        'createdAt': 1000,
      },
      // سجل عادي للمقارنة.
      {
        'id': 'RM',
        'name': 'م',
        'date': today,
        'payment': 'كاش',
        'amount': 100,
        'createdAt': 1001,
      },
    ];
    final rows = todayLedgerRows(records, const [], const []);
    expect(rows.length, 1);
    expect(rows.first.name, 'م');
    expect(ledgerTotals(rows).paid, 100); // قيمة none خارج الدخل اليومي.

    // دفعة دين يوم احتسابها none لا تدخل مدفوع صف الدين المدموج.
    final rows2 = todayLedgerRows([
      {
        'id': 'R1',
        'name': 'ماجد',
        'date': today,
        'payment': 'دين',
        'isDebt': 1,
        'amount': 400,
        'createdAt': 1000,
      },
    ], const [], [
      {
        'id': 'D',
        'date': today,
        'recordId': 'R1',
        'payment': 'كاش',
        'total_amount': 400,
        'paid_amount': 150,
        'remaining': 250,
        'installments': [
          {'id': 'i1', 'amount': 100, 'date': today},
          {'id': 'i2', 'amount': 50, 'date': today, 'incomeDate': kNoIncomeDay},
        ],
      },
    ]);
    expect(rows2.length, 1);
    expect(rows2.first.paid, 100); // قسط none مستبعد
    expect(rows2.first.remaining, 250); // المتبقي الحقيقي سليم (المالية سليمة)
  });

  test('م99: هوية الصف — المعرف والنوع والهاتف لقائمة الخيارات', () {
    final today = getCurrentDate();
    final records = <Map<String, Object?>>[
      {
        'id': 'R1',
        'name': 'أ',
        'phone': '0911',
        'date': today,
        'payment': 'كاش',
        'amount': 100,
        'createdAt': 1000,
      },
      {
        'id': 'R2',
        'name': 'س',
        'date': today,
        'isDebtPayment': 1,
        'debtId': 'OLD',
        'payment': 'كاش',
        'amount': 50,
        'createdAt': 2000,
      },
    ];
    final pros = <Map<String, Object?>>[
      {
        'id': 'P1',
        'name': 'ب',
        'phone': '0922',
        'date': today,
        'total': 300,
        'payment': 'تحويل',
        'createdAt': 1500,
      },
    ];
    final rows = todayLedgerRows(
        records, pros, [
      {'id': 'OLD', 'date': '2020-01-01', 'remaining': 10},
    ]);
    expect(rows.length, 3);
    expect(rows[0].id, 'R1');
    expect(rows[0].kind, 'r');
    expect(rows[0].phone, '0911');
    expect(rows[1].id, 'P1');
    expect(rows[1].kind, 'p');
    expect(rows[1].phone, '0922');
    expect(rows[2].id, 'R2');
    expect(rows[2].kind, 'dp');
  });

  test('دمج دين اليوم في صفٍّ واحد بطريقة الدفع الحقيقية (بلا تكرار)', () {
    final today = getCurrentDate();
    final records = <Map<String, Object?>>[
      {
        // كما يكتبه record_saver فعلاً: لا debtId على سجل الأصل.
        'id': 'R1',
        'name': 'ماجد',
        'date': today,
        'service': 'تركيب',
        'payment': 'دين',
        'isDebt': 1,
        'amount': 400,
        'createdAt': 1000,
      },
      {
        'name': 'ماجد',
        'date': today,
        'service': 'دفعة أولى',
        'isDebtPayment': 1,
        'debtId': 'D',
        'payment': 'كاش',
        'amount': 100,
        'createdAt': 1001,
      },
    ];
    final debts = <Map<String, Object?>>[
      {
        'id': 'D',
        'date': today,
        'recordId': 'R1',
        'payment': 'كاش',
        'total_amount': 400,
        'paid_amount': 100,
        'remaining': 300,
      },
    ];
    final rows = todayLedgerRows(records, const [], debts);
    expect(rows.length, 1); // صفّ واحد فقط (الدفعة الأولى مدموجة)
    expect(rows.first.payment, 'كاش'); // الطريقة الحقيقية لا «دين»
    expect(rows.first.value, 400);
    expect(rows.first.paid, 100);
    expect(rows.first.remaining, 300);
    expect(ledgerTotals(rows).paid, 100); // لا ازدواج في المدفوع
  });

  test('م130 — القيمة = المستحق لحظة الدفعة (سيناريو محمد الخالد)', () {
    final today = getCurrentDate();
    // دين 5,000: دفعتان سابقتان 500 و1,500 ثم دفعة اليوم 2,500 ⇒
    // المستحق لحظة دفعة اليوم 3,000 والمتبقي بعدها 500.
    final records = <Map<String, Object?>>[
      {
        'id': 'p3',
        'name': 'محمد الخالد',
        'date': today,
        'isDebtPayment': 1,
        'debtId': 'DK',
        'payment': 'كاش',
        'amount': 2500,
        'createdAt': 9000,
      },
    ];
    final debts = <Map<String, Object?>>[
      {
        'id': 'DK',
        'date': '2026-07-15',
        'total_amount': 5000,
        'paid_amount': 4500,
        'remaining': 500,
        'installments': [
          {'id': 'i1', 'recordId': 'p1', 'amount': 500, 'createdAt': 1000},
          {'id': 'i2', 'recordId': 'p2', 'amount': 1500, 'createdAt': 2000},
          {'id': 'i3', 'recordId': 'p3', 'amount': 2500, 'createdAt': 9000},
        ],
      },
    ];
    final rows = todayLedgerRows(records, const [], debts);
    expect(rows.length, 1);
    expect(rows.first.value, 3000); // المستحق لحظة الدفعة
    expect(rows.first.paid, 2500);
    expect(rows.first.remaining, 500); // القيمة − المدفوع = المتبقي
  });

  test('م131 — دفعتان بنفس اليوم على دينٍ قديم: باقي كل سطرٍ لحظته، '
      'والدمج الاختياري سطرٌ واحد بمجموعهما', () {
    final today = getCurrentDate();
    // دين 400 قديم: دفعة 50 ثم 200 اليوم ⇒ متبقٍ نهائي 150.
    final records = <Map<String, Object?>>[
      {
        'id': 'w1', 'name': 'محمد حسن', 'date': today,
        'isDebtPayment': 1, 'debtId': 'MH', 'payment': 'تحويل',
        'amount': 50, 'createdAt': 1000,
      },
      {
        'id': 'w2', 'name': 'محمد حسن', 'date': today,
        'isDebtPayment': 1, 'debtId': 'MH', 'payment': 'تحويل',
        'amount': 200, 'createdAt': 2000,
      },
    ];
    final debts = <Map<String, Object?>>[
      {
        'id': 'MH', 'date': '2026-07-20',
        'total_amount': 400, 'paid_amount': 250, 'remaining': 150,
        'installments': [
          {'id': 'j1', 'recordId': 'w1', 'amount': 50, 'createdAt': 1000},
          {'id': 'j2', 'recordId': 'w2', 'amount': 200, 'createdAt': 2000},
        ],
      },
    ];
    // م132 — الافتراضي مدموج؛ الوضع المنفصل يبقى موثقاً بالعلم صراحةً:
    // سطران، باقي كلٍّ = قيمته − مدفوعه.
    final sep =
        todayLedgerRows(records, const [], debts, mergeDebtPays: false);
    expect(sep.length, 2);
    expect(sep[0].value, 400); // المستحق لحظة الأولى
    expect(sep[0].paid, 50);
    expect(sep[0].remaining, 350); // لا 150 المشترك — علة البلاغ
    expect(sep[1].value, 350); // المستحق لحظة الثانية
    expect(sep[1].paid, 200);
    expect(sep[1].remaining, 150);
    expect(ledgerTotals(sep).paid, 250);

    // مدموج (الافتراضي م132): سطرٌ واحد بمجموع اليوم والمستحق أولاً.
    final mrg = todayLedgerRows(records, const [], debts);
    expect(mrg.length, 1);
    expect(mrg.first.value, 400);
    expect(mrg.first.paid, 250);
    expect(mrg.first.remaining, 150);
    expect(mrg.first.service.contains('×2'), isTrue);
    expect(ledgerTotals(mrg).paid, 250); // نفس مجموع اليوم في الوضعين
  });

  test('م132 — دينان مختلفان لنفس المريض يبقيان سطرين رغم الدمج', () {
    final today = getCurrentDate();
    final records = <Map<String, Object?>>[
      {
        'id': 'q1', 'name': 'سمير', 'date': today, 'isDebtPayment': 1,
        'debtId': 'D-A', 'payment': 'كاش', 'amount': 100, 'createdAt': 1000,
      },
      {
        'id': 'q2', 'name': 'سمير', 'date': today, 'isDebtPayment': 1,
        'debtId': 'D-B', 'payment': 'تحويل', 'amount': 40, 'createdAt': 2000,
      },
    ];
    final debts = <Map<String, Object?>>[
      {'id': 'D-A', 'date': '2026-07-01', 'total_amount': 300, 'remaining': 200},
      {'id': 'D-B', 'date': '2026-06-01', 'total_amount': 90, 'remaining': 50},
    ];
    final rows = todayLedgerRows(records, const [], debts);
    expect(rows.length, 2); // الدمج بمعرف الدين لا بالاسم
    expect(ledgerTotals(rows).paid, 140);
  });

  test('دفعة على دينٍ قديم تظهر صفاً مستقلاً بعنوان «دفعة دين»', () {
    final today = getCurrentDate();
    final records = <Map<String, Object?>>[
      {
        'name': 'سالم',
        'date': today,
        'service': 'سداد',
        'isDebtPayment': 1,
        'debtId': 'OLD',
        'payment': 'كاش',
        'amount': 70,
        'createdAt': 2000,
      },
    ];
    final debts = <Map<String, Object?>>[
      {
        'id': 'OLD',
        'date': '2020-01-01',
        'total_amount': 500,
        'paid_amount': 370,
        'remaining': 130,
      },
    ];
    final rows = todayLedgerRows(records, const [], debts);
    expect(rows.length, 1);
    expect(rows.first.payment, 'دفعة دين');
    // م130 — «القيمة» المستحق لحظة الدفعة: بلا قائمة أقساط يُشتق من
    // المتبقي الحالي + الدفعة (130 + 70 = 200)؛ فالقيمة − المدفوع
    // = المتبقي.
    expect(rows.first.value, 200);
    expect(rows.first.paid, 70);
    expect(rows.first.remaining, 130);
  });

  test('توافق قديم: سجل يحمل debtId مباشرةً ما زال يُربط بدينه', () {
    final today = getCurrentDate();
    final records = <Map<String, Object?>>[
      {
        'name': 'وليد',
        'date': today,
        'payment': 'دين',
        'isDebt': 1,
        'debtId': 'L', // بيانات قديمة (ما قبل record_saver الحالي).
        'amount': 300,
        'createdAt': 1000,
      },
    ];
    final debts = <Map<String, Object?>>[
      {
        'id': 'L',
        'payment': 'كاش',
        'total_amount': 300,
        'paid_amount': 50,
        'remaining': 250,
      },
    ];
    final rows = todayLedgerRows(records, const [], debts);
    expect(rows.length, 1);
    expect(rows.first.payment, 'كاش');
    expect(rows.first.value, 300);
    expect(rows.first.paid, 50);
    expect(rows.first.remaining, 250);
  });

  test('دين بلا أي دفعة يبقى بعنوان «دين» والمتبقي كامل القيمة', () {
    final today = getCurrentDate();
    final records = <Map<String, Object?>>[
      {
        'id': 'RZ',
        'name': 'زهير',
        'date': today,
        'payment': 'دين',
        'isDebt': 1,
        'amount': 500,
        'createdAt': 1000,
      },
    ];
    final debts = <Map<String, Object?>>[
      {
        'id': 'Z',
        'recordId': 'RZ',
        'payment': 'كاش', // الحفظ يكتب الطريقة دائماً حتى بلا دفعة أولى.
        'total_amount': 500,
        'paid_amount': 0,
        'remaining': 500,
      },
    ];
    final rows = todayLedgerRows(records, const [], debts);
    expect(rows.length, 1);
    expect(rows.first.payment, 'دين'); // لم يُدفع شيء ⇒ «دين».
    expect(rows.first.value, 500);
    expect(rows.first.paid, 0);
    expect(rows.first.remaining, 500);
  });
}
