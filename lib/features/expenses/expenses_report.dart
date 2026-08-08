/// بناء تقرير «استهلاك العيادة اليوم» — منطقٌ نقيّ مستقل عن حزمة pdf وعن
/// الواجهة، كي يُختبر بسهولة. الواجهة تمرّر صفوفه إلى `simpleTablePdf`.
library;

/// تسميات الفئات العربية المعروضة/المطبوعة.
const Map<String, String> kExpenseCategoryLabels = {
  'salary_withdrawal': 'رواتب',
  'cleaning': 'مواد التنظيف',
  'dental': 'مواد سنية',
  'other': 'أخرى',
};

String expenseCategoryLabel(Object? c) =>
    kExpenseCategoryLabels['${c ?? ''}'] ?? 'أخرى';

double expenseAmount(Object? v) =>
    v is num ? v.toDouble() : (double.tryParse('${v ?? ''}') ?? 0);

/// هل نوع الدفع نقديّ؟ (الغياب يُعامَل كاش — الافتراض المثبَّت.)
bool expenseIsCash(Object? payment) {
  final p = '${payment ?? 'كاش'}';
  return p.isEmpty || p == 'كاش' || p == 'نقد' || p == 'نقدي';
}

/// إجماليات مصروفات من صفوف: كلي/كاش/تحويل (نسخة نقيّة قابلة للاختبار،
/// توأم repo.monthExpenseTotals). أساس صافي الخزينة والأرباح.
({double total, double cash, double xfer}) expensesTotals(
    List<Map<String, Object?>> rows) {
  var total = 0.0, cash = 0.0, xfer = 0.0;
  for (final e in rows) {
    final a = expenseAmount(e['amount']);
    total += a;
    if (expenseIsCash(e['payment'])) {
      cash += a;
    } else {
      xfer += a;
    }
  }
  return (total: total, cash: cash, xfer: xfer);
}

/// جدول استهلاك اليوم الجاهز للطباعة.
class DailyConsumption {
  const DailyConsumption({
    required this.headers,
    required this.rows,
    required this.totRow,
    required this.total,
    required this.count,
  });

  final List<String> headers;
  final List<List<String>> rows;
  final List<String> totRow;
  final double total;
  final int count;
}

/// يبني صفوف تقرير استهلاك اليوم من بنود [items] (كل الفئات، شاملاً سحوبات
/// الرواتب). تُلحق [currency] بالمبالغ. الترتيب: الفئة ثم المبلغ تنازلياً.
DailyConsumption buildDailyConsumption(
  List<Map<String, Object?>> items, {
  String currency = '',
}) {
  final sorted = [...items]..sort((a, b) {
      final byCat =
          expenseCategoryLabel(a['category']).compareTo(expenseCategoryLabel(b['category']));
      if (byCat != 0) return byCat;
      return expenseAmount(b['amount']).compareTo(expenseAmount(a['amount']));
    });
  final cur = currency.trim().isEmpty ? '' : ' ${currency.trim()}';
  var total = 0.0;
  final rows = <List<String>>[];
  for (final e in sorted) {
    final amt = expenseAmount(e['amount']);
    total += amt;
    final title = '${e['title'] ?? ''}'.trim();
    final isDraw = '${e['category'] ?? ''}' == 'salary_withdrawal';
    rows.add([
      '${e['date'] ?? ''}', // تاريخ الصرف
      title.isEmpty ? expenseCategoryLabel(e['category']) : title,
      expenseCategoryLabel(e['category']),
      isDraw ? 'سحب' : 'مصروف', // النوع: سحب راتب أم مصروف عادي
      '${amt.toStringAsFixed(2)}$cur',
    ]);
  }
  return DailyConsumption(
    headers: const ['التاريخ', 'البند', 'الفئة', 'النوع', 'المبلغ'],
    rows: rows,
    totRow: ['', 'المجموع', '', '', '${total.toStringAsFixed(2)}$cur'],
    total: total,
    count: sorted.length,
  );
}
