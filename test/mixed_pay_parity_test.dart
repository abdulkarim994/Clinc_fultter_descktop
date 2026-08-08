/// م-تكافؤ — الدفعة المختلطة (كاش + تحويل معاً) في دفتر اليوم.
///
///  قرار المالك (مهمة التكافؤ هاتف/كمبيوتر): حين يدفع المريض على نفس
///  الدين بطريقتين في اليوم يبقى الصف مدموجاً واحداً، لكن:
///    ١) أجزاء الطرق تُحفظ على الصف (payParts) وتُعرض تفصيلاً.
///    ٢) بطاقات التوزيع تُحسب بالأجزاء الحقيقية لا بطريقة آخر دفعة.
///    ٣) فلترة «كاش» تعرض جزء الكاش وحده، و«تحويل» جزء التحويل وحده —
///       لا دمج بين الطريقتين أثناء الفلترة.
///    ٤) قائمة خيارات الدفع تعرض الطريقتين متى وُجد صفٌّ مختلط.
library;

import 'package:dental_clinic_flutter/core/utils/js_compat.dart'
    show getCurrentDate;
import 'package:dental_clinic_flutter/features/records/home_logic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final today = getCurrentDate();

  List<Map<String, Object?>> mixedRecords() => [
        {
          'id': 'x1', 'name': 'سالم علي', 'date': today,
          'isDebtPayment': 1, 'debtId': 'DX', 'payment': 'كاش',
          'amount': 300, 'createdAt': 1000,
        },
        {
          'id': 'x2', 'name': 'سالم علي', 'date': today,
          'isDebtPayment': 1, 'debtId': 'DX', 'payment': 'تحويل',
          'amount': 200, 'createdAt': 2000,
        },
      ];

  List<Map<String, Object?>> mixedDebts() => [
        {
          'id': 'DX', 'date': '2026-07-01',
          'total_amount': 800, 'paid_amount': 500, 'remaining': 300,
          'installments': [
            {'id': 'i1', 'recordId': 'x1', 'amount': 300, 'createdAt': 1000},
            {'id': 'i2', 'recordId': 'x2', 'amount': 200, 'createdAt': 2000},
          ],
        },
      ];

  test('الدمج يحفظ أجزاء الطرق: صفٌّ واحد بأجزاء كاش/تحويل الحقيقية', () {
    final rows = todayLedgerRows(mixedRecords(), const [], mixedDebts());
    expect(rows.length, 1, reason: 'نفس الدين ⇒ صف واحد رغم اختلاف الطرق');
    final r = rows.first;
    expect(r.paid, 500);
    expect(r.isMixedPay, isTrue);
    expect(r.payParts, {'كاش': 300, 'تحويل': 200});
    expect(r.service.contains('×2'), isTrue);
  });

  test('التوزيع بالأجزاء: بطاقة كاش تأخذ 300 وتحويل 200 (لا الكل للأخيرة)',
      () {
    final rows = todayLedgerRows(mixedRecords(), const [], mixedDebts());
    final tot = ledgerTotals(rows);
    expect(tot.paid, 500);
    expect(tot.paidBy['كاش'], 300,
        reason: 'قبل الإصلاح كان المجموع كله يُنسب لطريقة آخر دفعة');
    expect(tot.paidBy['تحويل'], 200);
  });

  test('فلترة «كاش» تعرض جزء الكاش وحده — و«تحويل» جزءه — بلا دمج', () {
    final rows = todayLedgerRows(mixedRecords(), const [], mixedDebts());

    final cash = filterLedgerRows(rows, payments: {'كاش'});
    expect(cash.length, 1);
    expect(cash.first.paid, 300, reason: 'جزء الكاش فقط');
    expect(cash.first.value, 300);
    expect(cash.first.isMixedPay, isFalse);
    expect(cash.first.effectiveMethod, 'كاش');
    expect(cash.first.remaining, 300,
        reason: 'متبقي الدين الحقيقي يبقى كما هو');

    final xfer = filterLedgerRows(rows, payments: {'تحويل'});
    expect(xfer.length, 1);
    expect(xfer.first.paid, 200, reason: 'جزء التحويل فقط');
    expect(xfer.first.effectiveMethod, 'تحويل');

    // مجموعا الفلترتين = مجموع الصف المدموج (لا فقد ولا ازدواج).
    expect(cash.first.paid + xfer.first.paid, 500);
  });

  test('فلترة تسمية «دفعة دين» تعرض الصف المدموج كاملاً بلا إسقاط', () {
    final rows = todayLedgerRows(mixedRecords(), const [], mixedDebts());
    final byLabel = filterLedgerRows(rows, payments: {'دفعة دين'});
    expect(byLabel.length, 1);
    expect(byLabel.first.paid, 500);
    expect(byLabel.first.isMixedPay, isTrue);
  });

  test('خيارات الدفع تشمل الطريقتين من الصف المختلط', () {
    final rows = todayLedgerRows(mixedRecords(), const [], mixedDebts());
    final opts = ledgerPayOptions(rows);
    expect(opts, containsAll(['كاش', 'تحويل', 'دفعة دين']));
  });

  test('دفعتان بنفس الطريقة: لا أجزاء (السلوك القديم حرفياً)', () {
    final recs = mixedRecords()
        .map((r) => {...r, 'payment': 'تحويل'})
        .toList();
    final rows = todayLedgerRows(recs, const [], mixedDebts());
    expect(rows.length, 1);
    expect(rows.first.isMixedPay, isFalse);
    expect(rows.first.payParts, isEmpty);
    expect(rows.first.effectiveMethod, 'تحويل');
    final tot = ledgerTotals(rows);
    expect(tot.paidBy['تحويل'], 500);
    expect(tot.paidBy.containsKey('كاش'), isFalse);
  });

  test('دين اليوم بدفعتين مختلفتين: صف الأصل يحمل الأجزاء أيضاً', () {
    // دين أُنشئ اليوم بدفعة أولى كاش 300 ثم دفعة تحويل 200 في اليوم نفسه:
    // يبقى صفاً واحداً (صف الأصل) وبأجزاء الطريقتين.
    final records = <Map<String, Object?>>[
      {
        'id': 'org', 'name': 'هدى منصور', 'date': today,
        'payment': 'دين', 'isDebt': 1, 'amount': 800, 'createdAt': 500,
      },
      {
        'id': 'f1', 'name': 'هدى منصور', 'date': today,
        'isDebtPayment': 1, 'debtId': 'DT', 'payment': 'كاش',
        'amount': 300, 'createdAt': 1000,
      },
      {
        'id': 'f2', 'name': 'هدى منصور', 'date': today,
        'isDebtPayment': 1, 'debtId': 'DT', 'payment': 'تحويل',
        'amount': 200, 'createdAt': 2000,
      },
    ];
    final debts = <Map<String, Object?>>[
      {
        'id': 'DT', 'date': today, 'recordId': 'org', 'payment': 'كاش',
        'total_amount': 800, 'paid_amount': 500, 'remaining': 300,
        'installments': [
          {'id': 'i1', 'recordId': 'f1', 'amount': 300, 'createdAt': 1000,
            'date': today},
          {'id': 'i2', 'recordId': 'f2', 'amount': 200, 'createdAt': 2000,
            'date': today},
        ],
      },
    ];
    final rows = todayLedgerRows(records, const [], debts);
    expect(rows.length, 1, reason: 'دفعات دين اليوم مدموجة في صف الأصل');
    final r = rows.first;
    expect(r.paid, 500);
    expect(r.payParts, {'كاش': 300, 'تحويل': 200});
    final tot = ledgerTotals(rows);
    expect(tot.paidBy['كاش'], 300);
    expect(tot.paidBy['تحويل'], 200);
  });
}
