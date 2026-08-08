/// منطق الرواتب — دوالٌّ نقيّة قابلة للاختبار بلا واجهة ولا قاعدة.
library;

/// المتبقّي من راتب موظفٍ في شهر = الراتب الأساسي − مجموع سحوبات الشهر.
///
///  يُحسب من سحوبات الشهر وحده، فيصفّر تلقائياً مطلع كل شهر. لا يُقصد أن
///  يكون سالباً (السحب فوق المتبقّي ممنوع في [validateWithdrawal])، لكنه
///  يُحسب رياضياً كما هو ليكشف أي بيانات قديمة غير متّسقة.
double salaryRemaining({
  required double baseSalary,
  required double withdrawnThisMonth,
}) =>
    baseSalary - withdrawnThisMonth;

/// نتيجة التحقّق من سحبٍ مقترح.
typedef WithdrawalCheck = ({bool ok, String? error});

/// هل يُسمح بسحب [amount] من راتبٍ متبقّيه هذا الشهر [remaining]؟
///
///  القرار المثبَّت (المالك): تُسمح عدّة سحوبات خلال الشهر ما دام مجموعها
///  لا يتجاوز راتب الشهر — أي لا يتجاوز السحبُ الواحد المتبقّي الحالي. وأي
///  تجاوز **يُمنع** (السقف = راتب الشهر).
WithdrawalCheck validateWithdrawal({
  required double amount,
  required double remaining,
}) {
  if (!amount.isFinite || amount <= 0) {
    return (ok: false, error: 'أدخل مبلغاً أكبر من صفر');
  }
  if (amount > remaining + 1e-6) {
    return (
      ok: false,
      error:
          'المبلغ يتجاوز المتبقّي المتاح (${remaining.toStringAsFixed(2)})',
    );
  }
  return (ok: true, error: null);
}

/// عدد الأشهر الشاملة من [start] إلى [end] (كلاهما `YYYY-MM`)، بحدٍّ أدنى 1.
/// (يُستعمل في سياسة الترحيل لحساب الراتب المستحقّ منذ شهر انضمام الموظف.)
int monthsInclusive(String start, String end) {
  int idx(String m) {
    final p = m.split('-');
    return int.parse(p[0]) * 12 + (int.parse(p[1]) - 1);
  }

  final d = idx(end) - idx(start) + 1;
  return d < 1 ? 1 : d;
}

/// المتبقّي وفق سياسة الرواتب المختارة:
///   • التصفير الشهري ([carryover] = false، الافتراضي): `base − مسحوب الشهر`.
///   • الترحيل ([carryover] = true): `base × أشهر − المسحوب التراكمي حتى الشهر`
///     — فالمتبقّي غير المسحوب يتراكم من شهرٍ لآخر منذ شهر الانضمام.
double salaryRemainingPolicy({
  required bool carryover,
  required double baseSalary,
  required double withdrawnThisMonth,
  required int monthsElapsed,
  required double cumulativeWithdrawn,
}) =>
    carryover
        ? baseSalary * monthsElapsed - cumulativeWithdrawn
        : baseSalary - withdrawnThisMonth;
