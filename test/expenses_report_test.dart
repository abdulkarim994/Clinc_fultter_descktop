/// اختبار المرحلة 4 — بناء تقرير «استهلاك اليوم» (منطق نقيّ بلا قاعدة).
library;

import 'package:dental_clinic_flutter/features/expenses/expenses_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('التسميات العربية للفئات', () {
    expect(expenseCategoryLabel('salary_withdrawal'), 'رواتب');
    expect(expenseCategoryLabel('cleaning'), 'مواد التنظيف');
    expect(expenseCategoryLabel('dental'), 'مواد سنية');
    expect(expenseCategoryLabel('other'), 'أخرى');
    expect(expenseCategoryLabel('???'), 'أخرى');
  });

  test('buildDailyConsumption: مجموع وعدد وعملة، والوصف الفارغ يعود لاسم الفئة',
      () {
    final items = <Map<String, Object?>>[
      {'category': 'salary_withdrawal', 'title': 'سعاد', 'amount': 300, 'date': '2026-08-02'},
      {'category': 'cleaning', 'title': 'كلور', 'amount': 40, 'date': '2026-08-02'},
      {'category': 'dental', 'title': 'قفازات', 'amount': 60, 'date': '2026-08-03'},
      {'category': 'other', 'title': '', 'amount': 10, 'date': '2026-08-04'},
    ];
    final d = buildDailyConsumption(items, currency: 'د.ل');
    // الأعمدة: [التاريخ, البند, الفئة, النوع, المبلغ]
    expect(d.headers, ['التاريخ', 'البند', 'الفئة', 'النوع', 'المبلغ']);
    expect(d.count, 4);
    expect(d.total, closeTo(410, 1e-9));
    expect(d.totRow.length, 5);
    expect(d.totRow.last, '410.00 د.ل');
    // سطر سحب راتب: النوع «سحب» + التاريخ + اسم الموظف.
    final draw = d.rows.firstWhere((r) => r[2] == 'رواتب');
    expect(draw[3], 'سحب');
    expect(draw[0], '2026-08-02');
    expect(draw[1], 'سعاد');
    // سطر مصروف عادي: النوع «مصروف».
    final clean = d.rows.firstWhere((r) => r[2] == 'مواد التنظيف');
    expect(clean[3], 'مصروف');
    // العنوان الفارغ → اسم الفئة (عمود البند = المؤشر 1).
    final other = d.rows.firstWhere((r) => r[2] == 'أخرى');
    expect(other[1], 'أخرى');
  });

  test('قائمة فارغة → مجموع صفر', () {
    final d = buildDailyConsumption(const []);
    expect(d.count, 0);
    expect(d.total, 0);
    expect(d.rows, isEmpty);
    expect(d.totRow.last, '0.00');
  });

  test('expensesTotals: تقسيم كاش/تحويل والغياب يُعامَل كاش', () {
    final rows = <Map<String, Object?>>[
      {'amount': 100, 'payment': 'كاش'},
      {'amount': 40, 'payment': 'تحويل'},
      {'amount': 10}, // بلا نوع دفع → كاش
    ];
    final t = expensesTotals(rows);
    expect(t.total, closeTo(150, 1e-9));
    expect(t.cash, closeTo(110, 1e-9));
    expect(t.xfer, closeTo(40, 1e-9));
    expect(expenseIsCash(null), isTrue);
    expect(expenseIsCash('كاش'), isTrue);
    expect(expenseIsCash('تحويل'), isFalse);
  });
}
