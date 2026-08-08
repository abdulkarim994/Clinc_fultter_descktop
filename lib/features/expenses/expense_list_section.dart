/// قسم قائمة مصروفات (مواد التنظيف / المواد السنية / مصروفات أخرى).
///
///  قائمةٌ عامة لفئةٍ واحدة: بنودٌ للشهر المختار (وصف/مبلغ/تاريخ/ملاحظة) مع
///  إضافة/تعديل/حذف، ومجموعٌ فرعيٌّ للفئة. يشترك القسمُ الثلاثةُ في هذا
///  الودجت — الفئة وتسميتها وحدهما ما يختلف. قسم الرواتب مستقلّ
///  ([SalariesSection]) لأن منطقه (موظفون + متبقٍّ) مختلف.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/js_compat.dart' show getCurrentDate;
import '../../core/utils/uid.dart' show genId;
import '../../data/audit/audit_trail.dart' show recordAudit;
import 'expenses_screen.dart' show expensesRefreshProvider;
import '../records/day_close_store.dart' show confirmClosedDayWrite;
import '../staff/staff_gate.dart'
    show gateStaff, requestAdminSignature, staffAllowed;
import 'expenses_report.dart' show expenseIsCash;
import 'payment_picker.dart';
import '../staff/staff_session.dart' show staffCreatedBy;

String _money(num v) => v.toStringAsFixed(2);
double _numOf(Object? v) =>
    v is num ? v.toDouble() : (double.tryParse('${v ?? ''}') ?? 0);

class ExpenseListSection extends ConsumerWidget {
  const ExpenseListSection(
      {super.key, required this.category, required this.label});

  final String category;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(expensesRefreshProvider);
    final month = ref.watch(selectedMonthProvider);
    final repos = ref.watch(reposProvider);
    // م113 — الأحدث أعلى: بالتاريخ تنازلياً ثم الأحدث تسجيلاً.
    final items =
        [...repos.expenses.getByMonth(month, category: category)]..sort((a, b) {
      final c = '${b['date'] ?? ''}'.compareTo('${a['date'] ?? ''}');
      if (c != 0) return c;
      num ts(Map<String, Object?> x) =>
          (x['_mod'] as num?) ?? (x['created_at'] as num?) ?? 0;
      return ts(b).compareTo(ts(a));
    });
    final subtotal = repos.expenses.categoryTotal(month, category);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$label (${items.length})',
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: BrandColors.brandText)),
                    Text('مجموع الشهر: ${_money(subtotal)}',
                        style:
                            TextStyle(fontSize: 11.5, color: BrandColors.mut)),
                  ],
                ),
              ),
              FilledButton.icon(
                key: const Key('exp-add'),
                style: FilledButton.styleFrom(
                    backgroundColor: BrandColors.brand,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8)),
                onPressed: () => _itemDialog(context, ref),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('بند'),
              ),
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? _empty()
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 20),
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final e = items[i];
                    return _ItemRow(
                      title: '${e['title'] ?? ''}',
                      amount: _numOf(e['amount']),
                      // م115 — طريقة الدفع بجانب القيمة (الفارغ = كاش).
                      pay: expenseIsCash(e['payment'])
                          ? 'كاش'
                          : '${e['payment']}',
                      date: '${e['date'] ?? ''}',
                      note: '${e['note'] ?? ''}',
                      onEdit: () => _itemDialog(context, ref, existing: e),
                      // م121 — الزر يختفي كلياً بلا صلاحية الحذف
                      // (والحذف نفسه يتطلب توقيع الإدارة).
                      onDelete: staffAllowed('expenses.delete')
                          ? () => _delete(context, ref, e)
                          : null,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inbox_rounded, size: 46, color: BrandColors.faint),
              const SizedBox(height: 12),
              Text('لا بنود في $label لهذا الشهر',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: BrandColors.brandText)),
              const SizedBox(height: 6),
              Text('اضغط «بند» لإضافة أول مصروف.',
                  style: TextStyle(fontSize: 12.5, color: BrandColors.mut)),
            ],
          ),
        ),
      );

  Future<void> _itemDialog(BuildContext context, WidgetRef ref,
      {Map<String, Object?>? existing}) async {
    // م119 — إضافة/تعديل المصروفات صلاحية مستقلة.
    if (!gateStaff(context, 'expenses.add')) return;
    final month = ref.read(selectedMonthProvider);
    final titleC = TextEditingController(text: '${existing?['title'] ?? ''}');
    final amountC = TextEditingController(
        text: existing == null ? '' : _money(_numOf(existing['amount'])));
    final noteC = TextEditingController(text: '${existing?['note'] ?? ''}');
    final today = getCurrentDate();
    var date = existing != null
        ? '${existing['date'] ?? today}'
        : (today.startsWith(month) ? today : '$month-01');
    String? error;
    final editing = existing != null;
    var payment = '${existing?['payment'] ?? ''}'.trim();
    if (payment.isEmpty) payment = 'كاش';

    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => StatefulBuilder(
        builder: (dctx, setLocal) => AlertDialog(
          title: Text(editing ? 'تعديل بند — $label' : 'بند جديد — $label'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('exp-title'),
                controller: titleC,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'الوصف'),
              ),
              TextField(
                key: const Key('exp-amount'),
                controller: amountC,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration:
                    InputDecoration(labelText: 'المبلغ', errorText: error),
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
                    helpText: 'تاريخ البند',
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
                decoration:
                    const InputDecoration(labelText: 'ملاحظة (اختياري)'),
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
              key: const Key('exp-save'),
              onPressed: () {
                final amt = double.tryParse(amountC.text.trim()) ?? 0;
                if (amt <= 0) {
                  setLocal(() => error = 'أدخل مبلغاً أكبر من صفر');
                  return;
                }
                Navigator.pop(dctx, true);
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final amt = double.tryParse(amountC.text.trim()) ?? 0;
    if (amt <= 0) return;
    final repos = ref.read(reposProvider);
    // م117 — مصروفٌ بتاريخ يومٍ مقفول؟ تنبيه ومتابعة بالتأكيد فقط.
    if (context.mounted &&
        !await confirmClosedDayWrite(context, repos.settings, date)) {
      return;
    }
    final id = editing ? '${existing['id']}' : genId();
    repos.expenses.upsertLocal({
      'id': id,
      // م120 — هوية المُدخِل (تبقى هوية المنشئ الأصلي عند التعديل عبر base).
      if (!editing) 'createdBy': ?staffCreatedBy(),
      'category': category,
      'title': titleC.text.trim(),
      'amount': amt,
      'date': date,
      'payment': payment,
      'note': noteC.text.trim(),
    }, base: existing);
    recordAudit(repos.db,
        action: editing ? 'expense.edit' : 'expense.add',
        entity: 'expenses',
        entityId: id,
        detail: {'category': category, 'amount': amt});
    ref.read(expensesRefreshProvider.notifier).state++;
  }

  Future<void> _delete(
      BuildContext context, WidgetRef ref, Map<String, Object?> e) async {
    // م119 — حذف المصروف صلاحية مستقلة.
    if (!gateStaff(context, 'expenses.delete')) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('حذف البند'),
        content: Text(
            'حذف «${'${e['title'] ?? ''}'.trim().isEmpty ? label : e['title']}» بمبلغ ${_money(_numOf(e['amount']))}؟'),
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
    // م117 — حذف مصروفٍ بتاريخ يومٍ مقفول؟ تنبيه ومتابعة بالتأكيد فقط.
    if (context.mounted &&
        !await confirmClosedDayWrite(
            context, repos.settings, '${e['date'] ?? ''}')) {
      return;
    }
    // م119 — حذف مصروف الدرج يتطلب توقيع الإدارة حصراً (منع التلاعب).
    if (!context.mounted) return;
    final signer = await requestAdminSignature(context, repos.settings,
        repos.db,
        reason:
            'حذف بند مصروف بمبلغ ${_money(_numOf(e['amount']))} من $label');
    if (signer == null) return;
    repos.expenses.delete('${e['id']}');
    recordAudit(repos.db,
        action: 'expense.delete',
        entity: 'expenses',
        entityId: '${e['id']}',
        detail: {'admin': signer});
    ref.read(expensesRefreshProvider.notifier).state++;
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.title,
    required this.amount,
    required this.pay,
    required this.date,
    required this.note,
    required this.onEdit,
    this.onDelete,
  });

  final String title;
  final double amount;

  /// م115 — طريقة الدفع تُعرض تحت القيمة مباشرة.
  final String pay;
  final String date;
  final String note;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: BrandColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: BrandColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(_money(amount),
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: BrandColors.goldDark)),
                  Text(pay,
                      style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: BrandColors.mut2)),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title.trim().isEmpty ? '—' : title,
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: BrandColors.brandText)),
                    Text(
                      note.trim().isEmpty ? date : '$date • $note',
                      style: TextStyle(fontSize: 11, color: BrandColors.mut),
                    ),
                  ],
                ),
              ),
              // م121 — بلا صلاحية الحذف لا يظهر الزر أصلاً.
              if (onDelete != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'حذف',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded,
                      size: 20, color: BrandColors.red),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
