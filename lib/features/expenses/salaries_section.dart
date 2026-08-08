/// قسم «الرواتب» داخل شاشة المصروفات.
///
///  الموظفون برواتبهم الأساسية، وسحوبات مؤرّخة تُخصم من راتب الشهر، والمتبقّي
///  يُحسب ويُعرض شهرياً (يصفّر مطلع كل شهر). السحب فوق المتبقّي ممنوع
///  ([validateWithdrawal]). كل فعلٍ مالي يُسجَّل في سجلّ التدقيق.
///
///  البيانات غير تفاعلية (مستودعات خام)، فنعيد القراءة عند كل بناء ونحرّك
///  [expensesRefreshProvider] بعد كل تعديل ليُعاد بناء الشاشة ورأس الإجمالي.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/js_compat.dart' show getCurrentDate;
import '../../core/utils/uid.dart' show genId;
import '../desktop/desktop_gate.dart' show isDesktopUi;
import '../desktop/widgets/desktop_dialogs.dart' show showDesktopSideSheet;
import '../records/day_close_store.dart' show confirmClosedDayWrite;
import '../staff/staff_gate.dart'
    show gateStaff, requestAdminSignature, staffAllowed;
import '../../data/audit/audit_trail.dart' show recordAudit;
import '../../data/repositories/repositories.dart' show Repositories;
import 'expenses_screen.dart' show expensesRefreshProvider;
import 'payment_picker.dart';
import 'salaries_logic.dart';
import '../staff/staff_session.dart' show staffCreatedBy;

String _money(num v) => v.toStringAsFixed(2);
double _numOf(Object? v) => (v is num) ? v.toDouble() : (double.tryParse('${v ?? ''}') ?? 0);

/// لقطةُ راتبٍ محسوبة وفق السياسة النشطة (تصفير شهري / ترحيل).
class _SalaryView {
  const _SalaryView({
    required this.base,
    required this.accrued,
    required this.withdrawnThisMonth,
    required this.shownWithdrawn,
    required this.remaining,
    required this.months,
    required this.startMonth,
  });

  final double base; // الراتب الشهري الأساسي
  final double accrued; // المستحقّ (base في التصفير، base×أشهر في الترحيل)
  final double withdrawnThisMonth; // مسحوب الشهر الحالي
  final double shownWithdrawn; // المعروض (شهري/تراكمي حسب السياسة)
  final double remaining; // المتبقّي وفق السياسة
  final int months; // أشهر الاستحقاق منذ الانضمام
  final String startMonth; // شهر انضمام الموظف (YYYY-MM)
}

/// يحسب لقطة راتب موظفٍ للشهر [month] وفق سياسة [carryover].
_SalaryView _salaryView(
    Repositories repos, bool carryover, String month, Map<String, Object?> e) {
  final base = _numOf(e['base_salary']);
  final id = '${e['id']}';
  final created = '${e['created_at'] ?? ''}';
  final startMonth = created.length >= 7 ? created.substring(0, 7) : month;
  final months = monthsInclusive(startMonth, month);
  final withdrawnThisMonth = repos.expenses.salaryWithdrawn(month, id);
  final cumulative = repos.expenses.salaryWithdrawnThrough(month, id);
  final remaining = salaryRemainingPolicy(
    carryover: carryover,
    baseSalary: base,
    withdrawnThisMonth: withdrawnThisMonth,
    monthsElapsed: months,
    cumulativeWithdrawn: cumulative,
  );
  return _SalaryView(
    base: base,
    accrued: carryover ? base * months : base,
    withdrawnThisMonth: withdrawnThisMonth,
    shownWithdrawn: carryover ? cumulative : withdrawnThisMonth,
    remaining: remaining,
    months: months,
    startMonth: startMonth,
  );
}

class SalariesSection extends ConsumerWidget {
  const SalariesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(expensesRefreshProvider); // إعادة البناء بعد أي تعديل
    final month = ref.watch(selectedMonthProvider);
    final carryover = ref.watch(appConfigProvider)['salaryCarryover'] == true;
    final repos = ref.watch(reposProvider);
    final employees = repos.employees.getAllSorted();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
          child: Row(
            children: [
              Text('الموظفون (${employees.length})',
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: BrandColors.brandText)),
              const Spacer(),
              // م121 — إدارة موظفي الرواتب بصلاحية عرض الرواتب.
              if (staffAllowed('salaries.view'))
              FilledButton.icon(
                key: const Key('emp-add'),
                style: FilledButton.styleFrom(
                    backgroundColor: BrandColors.brand,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8)),
                onPressed: () => _employeeDialog(context, ref),
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                label: const Text('موظف'),
              ),
            ],
          ),
        ),
        Expanded(
          child: employees.isEmpty
              ? _empty(month)
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 20),
                  itemCount: employees.length,
                  itemBuilder: (_, i) {
                    final e = employees[i];
                    final v = _salaryView(repos, carryover, month, e);
                    return _EmployeeCard(
                      name: '${e['name'] ?? '—'}',
                      role: '${e['role'] ?? ''}',
                      base: v.base,
                      withdrawn: v.shownWithdrawn,
                      remaining: v.remaining,
                      carryover: carryover,
                      // م121 — بلا صلاحية الرواتب: المسحوب فقط.
                      showSalary: staffAllowed('salaries.view'),
                      onTap: () => _openEmployeeSheet(context, ref, e),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _empty(String month) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.groups_rounded, size: 46, color: BrandColors.faint),
              const SizedBox(height: 12),
              Text('لا يوجد موظفون بعد',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: BrandColors.brandText)),
              const SizedBox(height: 6),
              Text('أضف موظفاً براتبه الأساسي لتتمكّن من تسجيل سحوباته الشهرية.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12.5, height: 1.6, color: BrandColors.mut)),
            ],
          ),
        ),
      );

  // ── تفصيل الموظف: سحوبات الشهر + إجراءات ───────────────────────────────
  void _openEmployeeSheet(BuildContext context, WidgetRef ref, Map<String, Object?> emp) {
    final id = '${emp['id']}';
    // نسخة الكمبيوتر: نفس المحتوى في درج جانبي (Side Sheet) بدل الورقة
    // السفلية القابلة للسحب — مسار الهاتف كما هو حرفياً.
    final desk = isDesktopUi(context);
    Widget sheetContent(BuildContext sheetCtx) => Consumer(
        builder: (ctx, ref2, _) {
          ref2.watch(expensesRefreshProvider);
          final month = ref2.watch(selectedMonthProvider);
          final repos = ref2.watch(reposProvider);
          final carryover =
              ref2.watch(appConfigProvider)['salaryCarryover'] == true;
          final v = _salaryView(repos, carryover, month, emp);
          final remaining = v.remaining;
          final draws = repos.expenses.salaryWithdrawals(month, id);
          Widget list(ScrollController? scroll) => ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: [
                if (!desk)
                  Center(
                    child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                            color: BrandColors.line,
                            borderRadius: BorderRadius.circular(2))),
                  ),
                if (!desk) const SizedBox(height: 12),
                Text('${emp['name'] ?? '—'}',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: BrandColors.brandText)),
                if ('${emp['role'] ?? ''}'.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('${emp['role']}',
                        style:
                            TextStyle(fontSize: 12.5, color: BrandColors.mut)),
                  ),
                const SizedBox(height: 12),
                _StatRow(
                    base: v.accrued,
                    withdrawn: v.shownWithdrawn,
                    remaining: remaining,
                    showSalary: staffAllowed('salaries.view')),
                if (carryover)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                        'ترحيل مُفعَّل — المتبقّي تراكمي منذ ${v.startMonth} (${v.months} شهر).',
                        style:
                            TextStyle(fontSize: 11, color: BrandColors.mut)),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        key: const Key('emp-withdraw'),
                        style: FilledButton.styleFrom(
                            backgroundColor: BrandColors.brand,
                            foregroundColor: Colors.white),
                        onPressed: remaining > 0
                            ? () => _withdrawDialog(
                                ctx, ref2, emp, month, remaining)
                            : null,
                        icon: const Icon(Icons.payments_rounded, size: 18),
                        label: Text(remaining > 0 ? 'سحب من الراتب' : 'لا متبقٍّ'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // م121 — تعديل الموظف (راتبه) بصلاحية الرواتب،
                    // وحذفه بصلاحية الحذف — الزر يختفي كلياً بدونها.
                    if (staffAllowed('salaries.view'))
                      IconButton(
                        tooltip: 'تعديل الموظف',
                        onPressed: () =>
                            _employeeDialog(ctx, ref2, existing: emp),
                        icon: const Icon(Icons.edit_rounded,
                            color: BrandColors.brand),
                      ),
                    if (staffAllowed('expenses.delete'))
                      IconButton(
                        tooltip: 'حذف الموظف',
                        onPressed: () =>
                            _deleteEmployee(ctx, ref2, emp, sheetCtx),
                        icon: const Icon(Icons.delete_outline_rounded,
                            color: BrandColors.red),
                      ),
                  ],
                ),
                const Divider(height: 28),
                Text('سحوبات $month (${draws.length})',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: BrandColors.brandText)),
                const SizedBox(height: 6),
                if (draws.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    child: Text('لا سحوبات في هذا الشهر.',
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(fontSize: 12.5, color: BrandColors.mut)),
                  )
                else
                  for (final w in draws)
                    _WithdrawalRow(
                      amount: _numOf(w['amount']),
                      // م115 — طريقة الدفع بجانب قيمة السحب (الفارغ = كاش).
                      pay: '${w['payment'] ?? ''}'.trim().isEmpty
                          ? 'كاش'
                          : '${w['payment']}'.trim(),
                      date: '${w['date'] ?? ''}',
                      note: '${w['note'] ?? ''}',
                      // م121 — الزر يختفي كلياً بلا صلاحية الحذف
                      // (والحذف نفسه يتطلب توقيع الإدارة).
                      onDelete: staffAllowed('expenses.delete')
                          ? () => _deleteWithdrawal(ctx, ref2, w)
                          : null,
                    ),
              ],
            );
          if (desk) return list(null);
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: .7,
            maxChildSize: .95,
            builder: (_, scroll) => list(scroll),
          );
        },
      );
    if (desk) {
      showDesktopSideSheet<void>(
        context,
        title: 'موظف الرواتب — ${emp['name'] ?? '—'}',
        width: 480,
        builder: sheetContent,
      );
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: BrandColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: sheetContent,
    );
  }

  // ── إضافة/تعديل موظف ───────────────────────────────────────────────────
  Future<void> _employeeDialog(BuildContext context, WidgetRef ref,
      {Map<String, Object?>? existing}) async {
    // م121 — إدارة موظفي الرواتب (راتب أساسي) بصلاحية عرض الرواتب.
    if (!gateStaff(context, 'salaries.view')) return;
    final nameC = TextEditingController(text: '${existing?['name'] ?? ''}');
    final roleC = TextEditingController(text: '${existing?['role'] ?? ''}');
    final salaryC = TextEditingController(
        text: existing == null ? '' : _money(_numOf(existing['base_salary'])));
    final editing = existing != null;

    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(editing ? 'تعديل موظف' : 'موظف جديد'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('emp-name'),
              controller: nameC,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'الاسم'),
            ),
            TextField(
              controller: roleC,
              decoration:
                  const InputDecoration(labelText: 'الوظيفة (تمريض/إداري…)'),
            ),
            TextField(
              key: const Key('emp-salary'),
              controller: salaryC,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration:
                  const InputDecoration(labelText: 'الراتب الأساسي الشهري'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('إلغاء')),
          FilledButton(
              key: const Key('emp-save'),
              onPressed: () => Navigator.pop(dctx, true),
              child: const Text('حفظ')),
        ],
      ),
    );
    if (ok != true) return;
    final name = nameC.text.trim();
    if (name.isEmpty) return;
    final salary = double.tryParse(salaryC.text.trim()) ?? 0;
    final repos = ref.read(reposProvider);
    final id = editing ? '${existing['id']}' : genId();
    repos.employees.upsertLocal({
      'id': id,
      'name': name,
      'role': roleC.text.trim(),
      'base_salary': salary,
      'active': 1,
      if (!editing) 'sort': DateTime.now().millisecondsSinceEpoch % 100000000,
    }, base: existing);
    recordAudit(repos.db,
        action: editing ? 'employee.edit' : 'employee.add',
        entity: 'employees',
        entityId: id,
        detail: {'base_salary': salary});
    ref.read(expensesRefreshProvider.notifier).state++;
  }

  Future<void> _deleteEmployee(
      BuildContext context, WidgetRef ref, Map<String, Object?> emp, BuildContext sheetCtx) async {
    // م119 — حذف الموظف ضمن صلاحية حذف المصروفات.
    if (!gateStaff(context, 'expenses.delete')) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('حذف الموظف'),
        content: Text(
            'حذف «${emp['name'] ?? ''}»؟ تبقى سحوباته المسجَّلة كسجلّ تاريخي في المصروفات.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('إلغاء')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: BrandColors.red),
              onPressed: () => Navigator.pop(dctx, true),
              child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    final repos = ref.read(reposProvider);
    repos.employees.delete('${emp['id']}');
    recordAudit(repos.db,
        action: 'employee.delete',
        entity: 'employees',
        entityId: '${emp['id']}');
    ref.read(expensesRefreshProvider.notifier).state++;
    if (sheetCtx.mounted) Navigator.pop(sheetCtx); // أغلق التفصيل
  }

  // ── سحب من الراتب ──────────────────────────────────────────────────────
  Future<void> _withdrawDialog(BuildContext context, WidgetRef ref, Map<String, Object?> emp,
      String month, double remaining) async {
    // م119 — تسجيل السحب ضمن صلاحية إضافة المصروفات.
    if (!gateStaff(context, 'expenses.add')) return;
    final amountC = TextEditingController();
    final noteC = TextEditingController();
    // التاريخ ضمن الشهر المختار: اليوم إن كان ضمنه، وإلا أوّل الشهر.
    final today = getCurrentDate();
    var date = today.startsWith(month) ? today : '$month-01';
    String? error;
    var payment = 'كاش';

    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => StatefulBuilder(
        builder: (dctx, setLocal) => AlertDialog(
          title: Text('سحب من راتب ${emp['name'] ?? ''}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text('المتبقّي المتاح: ${_money(remaining)}',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: BrandColors.brandText)),
              ),
              const SizedBox(height: 6),
              TextField(
                key: const Key('wd-amount'),
                controller: amountC,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                    labelText: 'المبلغ', errorText: error),
              ),
              const SizedBox(height: 6),
              InkWell(
                onTap: () async {
                  final parts = month.split('-');
                  final y = int.parse(parts[0]);
                  final m = int.parse(parts[1]);
                  final first = DateTime(y, m, 1);
                  final last = DateTime(y, m + 1, 0);
                  final init = DateTime.tryParse(date) ?? first;
                  final picked = await showDatePicker(
                    context: dctx,
                    initialDate: init.isBefore(first)
                        ? first
                        : (init.isAfter(last) ? last : init),
                    firstDate: first,
                    lastDate: last,
                    helpText: 'تاريخ السحب',
                  );
                  if (picked != null) {
                    date = '${picked.year.toString().padLeft(4, '0')}-'
                        '${picked.month.toString().padLeft(2, '0')}-'
                        '${picked.day.toString().padLeft(2, '0')}';
                    setLocal(() {});
                  }
                },
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'التاريخ'),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(date),
                      const Icon(Icons.calendar_month_rounded, size: 18),
                    ],
                  ),
                ),
              ),
              TextField(
                controller: noteC,
                decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)'),
              ),
              PaymentPicker(
                value: payment,
                onChanged: (v) => setLocal(() => payment = v),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dctx, false),
                child: const Text('إلغاء')),
            FilledButton(
              key: const Key('wd-save'),
              onPressed: () {
                final amt = double.tryParse(amountC.text.trim()) ?? 0;
                final check =
                    validateWithdrawal(amount: amt, remaining: remaining);
                if (!check.ok) {
                  setLocal(() => error = check.error);
                  return;
                }
                Navigator.pop(dctx, true);
              },
              child: const Text('سحب'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final amt = double.tryParse(amountC.text.trim()) ?? 0;
    final repos = ref.read(reposProvider);
    // م117 — سحبٌ بتاريخ يومٍ مقفول؟ تنبيه ومتابعة بالتأكيد فقط.
    if (context.mounted &&
        !await confirmClosedDayWrite(context, repos.settings, date)) {
      return;
    }
    final wid = genId();
    repos.expenses.upsertLocal({
      'id': wid,
      'createdBy': ?staffCreatedBy(), // م120 — هوية المُدخِل
      'category': 'salary_withdrawal',
      'employee_id': '${emp['id']}',
      'title': '${emp['name'] ?? ''}',
      'amount': amt,
      'date': date,
      'payment': payment,
      'note': noteC.text.trim(),
    });
    recordAudit(repos.db,
        action: 'salary.withdraw',
        entity: 'expenses',
        entityId: wid,
        detail: {'employee_id': '${emp['id']}', 'amount': amt, 'month': month});
    ref.read(expensesRefreshProvider.notifier).state++;
  }

  Future<void> _deleteWithdrawal(
      BuildContext context, WidgetRef ref, Map<String, Object?> w) async {
    // م119 — حذف السحب صلاحية مستقلة + توقيع الإدارة (منع التلاعب).
    if (!gateStaff(context, 'expenses.delete')) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('حذف السحب'),
        content: Text('حذف سحب بمبلغ ${_money(_numOf(w['amount']))}؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('إلغاء')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: BrandColors.red),
              onPressed: () => Navigator.pop(dctx, true),
              child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    final repos = ref.read(reposProvider);
    // م117 — حذف سحبٍ بتاريخ يومٍ مقفول؟ تنبيه ومتابعة بالتأكيد فقط.
    if (context.mounted &&
        !await confirmClosedDayWrite(
            context, repos.settings, '${w['date'] ?? ''}')) {
      return;
    }
    if (!context.mounted) return;
    final signer = await requestAdminSignature(context, repos.settings,
        repos.db,
        reason: 'حذف سحب راتب بمبلغ ${_money(_numOf(w['amount']))}');
    if (signer == null) return;
    repos.expenses.delete('${w['id']}');
    recordAudit(repos.db,
        action: 'salary.withdraw.delete',
        entity: 'expenses',
        entityId: '${w['id']}',
        detail: {'admin': signer});
    ref.read(expensesRefreshProvider.notifier).state++;
  }
}

class _EmployeeCard extends StatelessWidget {
  const _EmployeeCard({
    required this.name,
    required this.role,
    required this.base,
    required this.withdrawn,
    required this.remaining,
    required this.carryover,
    required this.onTap,
    this.showSalary = true,
  });

  final String name;
  final String role;
  final double base;
  final double withdrawn;
  final double remaining;
  final bool carryover;
  final VoidCallback onTap;

  /// م121 — بلا صلاحية الرواتب يُعرض المسحوب فقط (الراتب/المتبقي تُحجب).
  final bool showSalary;

  @override
  Widget build(BuildContext context) {
    final none = remaining <= 0.0001;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: BrandColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: BrandColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: BrandColors.brandText)),
                    const SizedBox(height: 2),
                    Text(
                      '${role.trim().isEmpty ? '' : '$role • '}'
                      '${showSalary ? 'الراتب ${_money(base)} • ' : ''}'
                      'مسحوب ${_money(withdrawn)}',
                      style: TextStyle(fontSize: 11.5, color: BrandColors.mut),
                    ),
                  ],
                ),
              ),
              if (showSalary)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(carryover ? 'المتبقّي (ترحيل)' : 'المتبقّي',
                        style:
                            TextStyle(fontSize: 10, color: BrandColors.mut)),
                    Text(_money(remaining),
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color:
                                none ? BrandColors.red : BrandColors.green)),
                  ],
                ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_left_rounded, color: BrandColors.gold),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow(
      {required this.base,
      required this.withdrawn,
      required this.remaining,
      this.showSalary = true});
  final double base;
  final double withdrawn;
  final double remaining;

  /// م121 — بلا صلاحية الرواتب تُعرض خانة المسحوب وحدها.
  final bool showSalary;

  @override
  Widget build(BuildContext context) {
    Widget cell(String label, double v, Color c) => Expanded(
          child: Column(
            children: [
              Text(label,
                  style: TextStyle(fontSize: 10.5, color: BrandColors.mut)),
              const SizedBox(height: 2),
              Text(_money(v),
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w900, color: c)),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: BrandColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: BrandColors.line),
      ),
      child: Row(
        children: [
          if (showSalary) cell('الراتب', base, BrandColors.brandText),
          cell('المسحوب', withdrawn, BrandColors.goldDark),
          if (showSalary)
            cell('المتبقّي', remaining,
                remaining <= 0.0001 ? BrandColors.red : BrandColors.green),
        ],
      ),
    );
  }
}

class _WithdrawalRow extends StatelessWidget {
  const _WithdrawalRow(
      {required this.amount,
      required this.pay,
      required this.date,
      required this.note,
      this.onDelete});
  final double amount;

  /// م115 — طريقة الدفع تُعرض تحت قيمة السحب مباشرة.
  final String pay;
  final String date;
  final String note;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: BrandColors.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: BrandColors.line),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(_money(amount),
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: BrandColors.goldDark)),
              Text(pay,
                  style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: BrandColors.mut2)),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(date,
                    style:
                        TextStyle(fontSize: 11.5, color: BrandColors.brandText)),
                if (note.trim().isNotEmpty)
                  Text(note,
                      style: TextStyle(fontSize: 11, color: BrandColors.mut)),
              ],
            ),
          ),
          // م121 — بلا صلاحية الحذف لا يظهر الزر أصلاً (لا معطلاً).
          if (onDelete != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'حذف',
              onPressed: onDelete,
              icon: const Icon(Icons.close_rounded,
                  size: 18, color: BrandColors.red),
            ),
        ],
      ),
    );
  }
}
