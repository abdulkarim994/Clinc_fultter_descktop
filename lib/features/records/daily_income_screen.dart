/// شاشة «دخل اليوم» — تبويب الرئيسية الجديد: جدولٌ بصفٍّ لكل حالة/حدث دخلٍ
/// اليوم (علاجات + دفعات ديون)، مرتّبٌ بساعة التسجيل. الأعمدة: رقم · الساعة ·
/// الاسم · العيادة · نوع العلاج · الدفع · القيمة · المدفوع · المتبقي.
///
/// جدولٌ أفقي التمرير (نمط 2026 للجداول المالية على الهاتف) بأرقامٍ جدولية
/// ومحاذاة RTL. الإدخال الجديد انتقل بالكامل إلى زر «+» العائم (ورقة سفلية).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/display_prefs.dart'
    show appDigits, formatClock, kPeriodCutoffHour;
import '../../core/utils/js_compat.dart' show getCurrentDate;
import '../../core/widgets/double_confirm.dart' show confirmDelete;
import '../../data/audit/audit_trail.dart' show recordAudit;
import '../expenses/expenses_report.dart'
    show expenseCategoryLabel, expenseIsCash;
import '../expenses/expenses_screen.dart' show expensesRefreshProvider;
import '../finance/finance_screen.dart' show financeRevProvider;
import '../patients/patient_profile_screen.dart' show PatientProfileScreen;
import '../patients/patients_tab.dart' show patientsRevProvider;
import '../patients/profile_actions.dart' show deleteEntryCascade;
import '../patients/quick_info_dialog.dart' show showQuickInfoDialog;
import '../patients/quick_visit_sheet.dart' show showQuickVisitSheet;
import '../print/print_service.dart' show loadPdfBrand, printOrSharePdf;
import '../print/reports.dart' show dayClosePdf, shiftReportPdf;
import '../print/treatment_tables.dart' show formatNumber;
import 'add_record_screen.dart' show openAddRecordSheet;
import 'day_close_store.dart' show DayCloseStore, confirmClosedDayWrite;
import 'home_logic.dart' hide JMap;
import 'pay_breakdown_dialog.dart' show MixedPayCell;
import '../staff/staff_gate.dart'
    show gateStaff, requestAdminSignature, staffAllowed;
import '../staff/staff_store.dart' show StaffStore;
import '../staff/staff_session.dart' show kCurrentStaff, staffIsAdmin;

// أوزان أعمدة جدول الدخل (تُستعمل في الرأس والصفوف معاً ليتطابق الرصف).
// بلا «نوع العلاج» — والجدول يملأ عرض الشاشة (لا تمرير أفقي).
const _fxNum = 6,
    _fxTime = 13,
    _fxName = 26,
    _fxClinic = 16,
    _fxPay = 16,
    _fxVal = 17,
    _fxPaid = 17,
    _fxRem = 17;

class DailyIncomeScreen extends ConsumerStatefulWidget {
  const DailyIncomeScreen({super.key});

  @override
  ConsumerState<DailyIncomeScreen> createState() => _DailyIncomeScreenState();
}

class _DailyIncomeScreenState extends ConsumerState<DailyIncomeScreen> {
  final _searchCtl = TextEditingController();
  String _query = '';
  final Set<String> _clinics = {};
  final Set<String> _payments = {};
  bool _onlyRemaining = false;
  // م113 — الافتراضي: الأحدث أولاً (خيارات الفرز باقية كاملة).
  LedgerSort _sort = LedgerSort.timeDesc;
  LedgerPeriod? _period; // null = كل اليوم
  bool _showExpenses = false;

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  int get _activeFilters =>
      _clinics.length + _payments.length + (_onlyRemaining ? 1 : 0);

  @override
  Widget build(BuildContext context) {
    ref.watch(patientsRevProvider); // يتحدّث بعد كل حفظ من ورقة الإدخال
    final repos = ref.watch(reposProvider);
    final cur = ref.watch(currencyProvider);
    final all = todayLedgerRows(
      repos.records.getAll(),
      repos.prosthetics.getAll(),
      repos.debts.getAll(),
    );
    final clinicOpts = (<String>{for (final r in all) r.clinic}.toList())
      ..sort();
    // م-تكافؤ — الخيارات تشمل طرق الأجزاء المختلطة (كاش/تحويل) أيضاً.
    final payOpts = ledgerPayOptions(all);
    final income = sortLedgerRows(
      filterLedgerRows(
        all,
        nameQuery: _query,
        clinics: _clinics,
        payments: _payments,
        onlyRemaining: _onlyRemaining,
        period: _period,
        cutoffHour: kPeriodCutoffHour,
      ),
      _sort,
    );
    final expenseRows = _showExpenses
        ? _todayExpenseRows(_period, _query)
        : const <LedgerRow>[];
    final rows = [...income, ...expenseRows];
    final tot = ledgerTotals(rows);

    return Column(
      children: [
        _Header(
          date: getCurrentDate(),
          tot: tot,
          cur: cur,
          showExpenses: _showExpenses,
          closed: _isTodayClosed(),
        ),
        _toolbar(clinicOpts, payOpts),
        _periodBar(),
        if (_activeFilters > 0) _activeChips(),
        Expanded(
          child: (all.isEmpty && expenseRows.isEmpty)
              ? _empty(
                  'لا دخل مسجّل اليوم',
                  'اضغط زر «+» لإضافة زيارة أو دفعة.',
                )
              : (rows.isEmpty
                    ? _empty('لا نتائج', 'جرّب تعديل البحث أو الفلاتر.')
                    : _LedgerTable(rows: rows, onRowMenu: _openRowMenu)),
        ),
      ],
    );
  }

  /// صفوف مصروفات اليوم (خصمٌ من الدخل) — تُلحَق بالجدول حين تُفعّل.
  List<LedgerRow> _todayExpenseRows(LedgerPeriod? period, String query) {
    final repos = ref.read(reposProvider);
    final today = getCurrentDate();
    final q = query.trim();
    final out = <LedgerRow>[];
    for (final e in repos.expenses.getByDay(today)) {
      final ms =
          (e['_mod'] as num?)?.toDouble() ??
          (e['createdAt'] as num?)?.toDouble() ??
          0;
      if (period != null &&
          ledgerPeriodOf(ms, cutoffHour: kPeriodCutoffHour) != period) {
        continue;
      }
      final title = '${e['title'] ?? ''}'.trim();
      final label = expenseCategoryLabel(e['category']);
      final name = title.isEmpty ? label : title;
      if (q.isNotEmpty && !name.contains(q)) continue;
      // م95 — طريقة دفع المصروف لتوزيع البطاقة: الفارغ/نقد ⇒ كاش
      // (نفس اعتبار تقارير المصروفات expenseIsCash).
      final pay = '${e['payment'] ?? ''}'.trim();
      out.add(
        LedgerRow(
          isExpense: true,
          name: name,
          clinic: '—',
          service: label,
          payment: 'مصروف',
          method: expenseIsCash(pay) ? 'كاش' : pay,
          id: '${e['id'] ?? ''}',
          kind: 'e',
          by: '${e['createdBy'] ?? ''}',
          timeMs: ms,
          value: (e['amount'] as num?)?.toDouble() ?? 0,
          paid: 0,
          remaining: 0,
        ),
      );
    }
    out.sort((a, b) => a.timeMs.compareTo(b.timeMs));
    return out;
  }

  // ═══ م99 — قائمة خيارات الصف (ضغط مطول / نقر يميني) ═══

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), duration: const Duration(milliseconds: 1600)),
  );

  void _openProfile(LedgerRow row) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PatientProfileScreen(
          patientName: row.name,
          clinic: row.clinic == kNoClinic ? '' : row.clinic,
        ),
      ),
    );
  }

  /// م120 — الاسم الظاهر لموظفٍ من اسم دخوله (يعيد اسم الدخول إن حُذف).
  String _staffDisplay(String username) {
    final u = StaffStore(ref.read(reposProvider).settings).byUsername(username);
    return u == null ? username : '${u['name']}';
  }

  Future<void> _openRowMenu(LedgerRow row) async {
    final n = formatNumber;
    // نظام «التحاليل» — تحاليل هذا الصف (إن وُجدت): الربط بالمعرّف ثم
    // بالاسم+اليوم (نفس منطق العرض). صفوف التحاليل محروسةٌ خارج الجدول.
    final analIndex =
        buildAnalysisIndex(ref.read(reposProvider).records.getAll());
    final rowAnalyses =
        analIndex.forRow(row.id, row.name, getCurrentDate());
    Widget item({
      required IconData icon,
      required String label,
      Color? color,
      required VoidCallback onTap,
    }) => ListTile(
      dense: true,
      leading: Icon(icon, size: 20, color: color ?? BrandColors.goldDark),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
          color: color ?? BrandColors.ink,
        ),
      ),
      onTap: onTap,
    );

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: BrandColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: BrandColors.line,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            // ترويسة: الاسم + سطر القيمة/الطريقة.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: row.isExpense
                          ? BrandColors.red
                          : BrandColors.brandText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    row.isExpense
                        ? 'مصروف • ${n(row.value)}'
                        : '${row.payment} • القيمة ${n(row.value)}'
                              '${row.remaining > 0 ? ' • متبقٍ ${n(row.remaining)}' : ''}',
                    style: TextStyle(fontSize: 11, color: BrandColors.mut),
                  ),
                  // م120 — هوية المُدخِل (createdBy) بالاسم الظاهر.
                  if (row.by.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'أضافه: ${_staffDisplay(row.by)}',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: BrandColors.goldDark,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Divider(height: 1, color: BrandColors.line),
            // م119 — البنود حسب صلاحيات الجلسة (الإدارة ترى الكل).
            if (!row.isExpense) ...[
              if (staffAllowed('patients.view'))
                item(
                  icon: Icons.person_rounded,
                  label: 'فتح ملف المريض',
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _openProfile(row);
                  },
                ),
              if (staffAllowed('records.add'))
                item(
                  icon: Icons.add_circle_rounded,
                  label: 'زيارة سريعة جديدة',
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    showQuickVisitSheet(
                      context,
                      name: row.name,
                      clinic: row.clinic == kNoClinic ? '' : row.clinic,
                      phone: row.phone,
                      onFullOptions: () => openAddRecordSheet(context),
                    );
                  },
                ),
              if (staffAllowed('records.edit'))
                item(
                  icon: Icons.edit_rounded,
                  label: 'تعديل السجل',
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _editRow(row);
                  },
                ),
              // معلومات مختصرة (قرار المالك): ملاحظة هذه الدفعة/الزيارة
              // حصراً — عرضٌ للجميع وتعديلٌ بصلاحية records.edit.
              if (row.id.isNotEmpty)
                item(
                  icon: Icons.sticky_note_2_outlined,
                  label: 'معلومات مختصرة',
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    showQuickInfoDialog(
                      context,
                      ref,
                      kind: row.kind,
                      id: row.id,
                      patientName: row.name,
                    );
                  },
                ),
              // نظام «التحاليل» — بندٌ يظهر فقط إن للصف تحليلٌ مرتبط: يفتح
              // نافذةً تعرض التحاليل (الاسم/القيمة/الطريقة). دخلٌ معزول.
              if (rowAnalyses.isNotEmpty)
                item(
                  icon: Icons.science_rounded,
                  label: 'التحاليل ✓',
                  color: BrandColors.green,
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _showRowAnalyses(row, rowAnalyses);
                  },
                ),
            ],
            item(
              icon: Icons.copy_rounded,
              label: 'نسخ الاسم',
              onTap: () {
                Navigator.pop(sheetCtx);
                Clipboard.setData(ClipboardData(text: row.name));
                _snack('نُسخ الاسم');
              },
            ),
            if (staffAllowed(
              row.isExpense ? 'expenses.delete' : 'records.delete',
            ))
              item(
                icon: Icons.delete_rounded,
                label: row.isExpense ? 'حذف المصروف' : 'حذف السجل',
                color: BrandColors.red,
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _deleteRow(row);
                },
              ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  /// نظام «التحاليل» — نافذةٌ تعرض تحاليل الصف (الاسم/القيمة/الطريقة).
  /// بلا أثرٍ مالي — عرضٌ بحت لدخلٍ مخبري معزول.
  Future<void> _showRowAnalyses(
      LedgerRow row, List<AnalysisLink> analyses) async {
    final n = formatNumber;
    final cur = ref.read(currencyProvider);
    await showDialog<void>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Row(children: [
          Icon(Icons.science_rounded, size: 18, color: BrandColors.green),
          const SizedBox(width: 6),
          Expanded(
            child: Text('تحاليل — ${row.name}',
                style: const TextStyle(fontSize: 14)),
          ),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final a in analyses)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Expanded(
                    child: Text(a.name,
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w700)),
                  ),
                  Text('${n(a.amount)} $cur',
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: BrandColors.green)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: (a.isCash
                              ? BrandColors.green
                              : const Color(0xFF8A6D1B))
                          .withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(a.payment,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: a.isCash
                                ? BrandColors.green
                                : const Color(0xFF8A6D1B))),
                  ),
                ]),
              ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx),
              child: const Text('إغلاق')),
        ],
      ),
    );
  }

  /// م100 — «تعديل السجل»: يفتح ورقة الإدخال معبأة ببيانات السجل كاملة،
  /// والحفظ يستبدل الأصل (إنشاء البديل ثم حذف متسلسل للأصل).
  Future<void> _editRow(LedgerRow row) async {
    if (row.id.isEmpty) {
      _snack('تعذّر تحديد الصف');
      return;
    }
    final repos = ref.read(reposProvider);
    if (row.kind == 'dp') {
      // دفعة دين: تُعدَّل من ملف المريض (سياق الدين وأقساطه كاملاً).
      _snack('دفعات الديون تُعدَّل من ملف المريض');
      _openProfile(row);
      return;
    }
    final raw = row.kind == 'p'
        ? repos.prosthetics.getById(row.id)
        : repos.records.getById(row.id);
    if (raw == null) {
      _snack('تعذّر جلب السجل');
      return;
    }
    final e = Map<String, Object?>.from(raw);
    Map<String, Object?>? d;
    final isDebtCase =
        e['payment'] == 'دين' ||
        e['isDebt'] == 1 ||
        e['isDebt'] == true ||
        e['isDebt'] == '1';
    if (isDebtCase) {
      final link = row.kind == 'p' ? 'prostheticId' : 'recordId';
      for (final x in repos.debts.getAll()) {
        final m = Map<String, Object?>.from(x as Map);
        if ('${m[link] ?? ''}' == row.id ||
            ('${e['debtId'] ?? ''}'.isNotEmpty &&
                '${m['id']}' == '${e['debtId']}')) {
          d = m;
          break;
        }
      }
      // دين بأقساط متعددة: الاستبدال يفقد الأقساط اللاحقة — يُوجَّه للملف.
      final inst = d?['installments'];
      if (inst is List && inst.length > 1) {
        _snack('لهذا الدين دفعات متعددة — عدّله من ملف المريض');
        _openProfile(row);
        return;
      }
    }
    if (!mounted) return;
    openAddRecordSheet(context, editEntry: e, editKind: row.kind, editDebt: d);
  }

  Future<void> _deleteRow(LedgerRow row) async {
    if (row.id.isEmpty) {
      _snack('تعذّر تحديد الصف');
      return;
    }
    final repos = ref.read(reposProvider);
    // م119 — صلاحية الحذف حسب نوع الصف.
    if (!gateStaff(
      context,
      row.isExpense ? 'expenses.delete' : 'records.delete',
    )) {
      return;
    }
    // م117 — الجدول يعرض يوم اليوم؛ فحذف صفٍّ يمسّ يوماً قد يكون مقفولاً.
    if (!mounted ||
        !await confirmClosedDayWrite(
          context,
          repos.settings,
          getCurrentDate(),
        )) {
      return;
    }
    if (!mounted) return;
    if (row.isExpense) {
      // نفس مسار حذف بند المصروفات (قائمة المصروفات) حرفياً.
      final ok = await showDialog<bool>(
        context: context,
        builder: (dctx) => AlertDialog(
          title: const Text('حذف البند'),
          content: Text('حذف «${row.name}» بمبلغ ${formatNumber(row.value)}؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: BrandColors.red),
              onPressed: () => Navigator.pop(dctx, true),
              child: const Text('حذف'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      // م119 — حذف مصروف الدرج يتطلب توقيع الإدارة حصراً (منع التلاعب).
      final signer = await requestAdminSignature(
        context,
        repos.settings,
        repos.db,
        reason: 'حذف مصروف «${row.name}» بمبلغ ${formatNumber(row.value)}',
      );
      if (signer == null || !mounted) return;
      repos.expenses.delete(row.id);
      recordAudit(
        repos.db,
        action: 'expense.delete',
        entity: 'expenses',
        entityId: row.id,
        detail: {'admin': signer},
      );
      ref.read(expensesRefreshProvider.notifier).state++;
      ref.read(financeRevProvider.notifier).state++;
      setState(() {});
      _snack('تم حذف المصروف');
      return;
    }
    // سجل/تركيبة/دفعة دين — نفس مسار ملف المريض حرفياً: حوار التأكيد
    // المعتاد ثم الحذف المتسلسل (يشمل الدين المرتبط).
    final ok = await confirmDelete(
      context,
      config: ref.read(appConfigProvider),
      type: 'rec',
      title: 'حذف السجل',
      msg: 'هل أنت متأكد من حذف هذا السجل؟',
    );
    if (!ok || !mounted) return;
    deleteEntryCascade(
      repos,
      ref.read(appConfigProvider),
      id: row.id,
      source: row.kind == 'p' ? 'p' : 'r',
    );
    ref.read(patientsRevProvider.notifier).state++;
    ref.read(financeRevProvider.notifier).state++;
    setState(() {});
    _snack('تم حذف السجل');
  }

  Widget _periodBar() {
    Widget seg(String label, LedgerPeriod? p) {
      final on = _period == p;
      return Padding(
        padding: const EdgeInsets.only(left: 6),
        child: ChoiceChip(
          label: Text(label, style: const TextStyle(fontSize: 12)),
          selected: on,
          onSelected: (_) => setState(() => _period = p),
        ),
      );
    }

    // م133 — الصف كان يفيض أفقياً (347ن بأقصى مقياس خط، ويلامس الفيضان
    // حتى على عرض 393dp القياسي): أربع رقاقات وSpacer في صفٍّ صلب.
    // الحل تمريرٌ أفقي عند الضيق فقط — الرقاقات أزرار لمس وتصغيرها
    // بـFittedBox يهبط بها تحت مقاس اللمس المريح. وعند السعة يبقى
    // التوزيع الأصلي حرفياً: قيد عرضٍ أدنى بعرض الشاشة + spaceBetween
    // يطابقان أثر Spacer القديم (المصروفات في أقصى اليسار)، إذ Spacer
    // نفسه محظور داخل عرضٍ غير محدود.
    return SizedBox(
      height: 46,
      child: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: box.maxWidth),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(width: 12),
                    seg('كل اليوم', null),
                    seg('صباحي', LedgerPeriod.morning),
                    seg('مسائي', LedgerPeriod.evening),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: FilterChip(
                    key: const Key('daily-expenses-toggle'),
                    avatar: Icon(
                      Icons.receipt_long_rounded,
                      size: 16,
                      color: _showExpenses ? Colors.white : BrandColors.mut,
                    ),
                    label: const Text(
                      'المصروفات',
                      style: TextStyle(fontSize: 12),
                    ),
                    selected: _showExpenses,
                    selectedColor: BrandColors.red,
                    labelStyle: TextStyle(
                      color: _showExpenses ? Colors.white : BrandColors.ink,
                      fontWeight: FontWeight.w700,
                    ),
                    onSelected: (v) => setState(() => _showExpenses = v),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _toolbar(List<String> clinicOpts, List<String> payOpts) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 42,
              child: TextField(
                controller: _searchCtl,
                onChanged: (v) => setState(() => _query = v),
                textAlignVertical: TextAlignVertical.center,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'بحث بالاسم',
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () {
                            _searchCtl.clear();
                            setState(() => _query = '');
                          },
                        ),
                  filled: true,
                  fillColor: BrandColors.surface,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          _ToolBtn(
            key: const Key('daily-filter'),
            icon: Icons.filter_list_rounded,
            badge: _activeFilters,
            onTap: () => _openFilter(clinicOpts, payOpts),
          ),
          const SizedBox(width: 4),
          PopupMenuButton<LedgerSort>(
            key: const Key('daily-sort'),
            tooltip: 'الفرز',
            initialValue: _sort,
            onSelected: (v) => setState(() => _sort = v),
            itemBuilder: (_) => [
              for (final e in ledgerSortLabels.entries)
                PopupMenuItem(value: e.key, child: Text(e.value)),
            ],
            child: const _ToolBtnShell(child: Icon(Icons.sort_rounded)),
          ),
          const SizedBox(width: 4),
          // م120 — تقرير تسليم الوردية (Z): مقبوضات الموظف ومصروفاته
          // ورصيد تسليم الدرج — للطباعة نهاية الدوام.
          if (staffAllowed('print'))
            _ToolBtn(
              key: const Key('shift-report'),
              icon: Icons.assignment_ind_rounded,
              badge: 0,
              onTap: _onShiftReport,
            ),
          if (staffAllowed('print')) const SizedBox(width: 4),
          // م104 — قفل اليوم: تحذير ← تقرير PDF وطباعة ← حالة قفل
          // متزامنة. مقفول = أيقونة قفل ذهبية والنقر يعرض إعادة الفتح.
          if (staffAllowed('dayclose') || staffAllowed('dayreopen'))
            _ToolBtn(
              key: const Key('daily-lock'),
              icon: _isTodayClosed()
                  ? Icons.lock_rounded
                  : Icons.lock_open_rounded,
              badge: 0,
              onTap: _onLockTap,
            ),
        ],
      ),
    );
  }

  // ═══ م120 — تقرير تسليم الوردية ═══

  /// اختيار الموظف (الإدارة تختار؛ الموظف تقريره فقط) ثم توليد التقرير.
  Future<void> _onShiftReport() async {
    if (!gateStaff(context, 'print')) return;
    final repos = ref.read(reposProvider);
    final me = kCurrentStaff;
    String username = '${me?['username'] ?? ''}';
    String display = '${me?['name'] ?? ''}';
    if (staffIsAdmin(me)) {
      final staff = StaffStore(repos.settings).listActive();
      String sel = username;
      final ok = await showDialog<bool>(
        context: context,
        builder: (dctx) => StatefulBuilder(
          builder: (dctx, setSt) => AlertDialog(
            title: const Text(
              'تقرير تسليم الوردية',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'مقبوضات الموظف ومصروفاته اليوم ورصيد تسليم الدرج.',
                  style: TextStyle(fontSize: 12, color: BrandColors.mut),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  key: const Key('shift-staff'),
                  isExpanded: true,
                  initialValue: sel,
                  decoration: const InputDecoration(labelText: 'الموظف'),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('كل الصفوف (اليوم كاملاً)'),
                    ),
                    for (final u in staff)
                      DropdownMenuItem(
                        value: '${u['username']}',
                        child: Text(
                          '${u['name']}'
                          '${'${u['shift'] ?? ''}'.isEmpty ? '' : ' (${u['shift']})'}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                  ],
                  onChanged: (v) => setSt(() => sel = v ?? sel),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dctx, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                key: const Key('shift-report-go'),
                style: FilledButton.styleFrom(
                  backgroundColor: BrandColors.brand600,
                ),
                onPressed: () => Navigator.pop(dctx, true),
                child: const Text('توليد وطباعة'),
              ),
            ],
          ),
        ),
      );
      if (ok != true || !mounted) return;
      username = sel;
      display = sel.isEmpty ? 'كل الموظفين' : _staffDisplay(sel);
    }
    await _printShiftReport(username, display);
  }

  /// توليد وطباعة تقرير الوردية: صفوف اليوم المنسوبة للموظف فقط
  /// (username فارغ = الكل)، بإجمالياتٍ توأم تقرير قفل اليوم.
  Future<void> _printShiftReport(String username, String display) async {
    final repos = ref.read(reposProvider);
    final today = getCurrentDate();
    final all = todayLedgerRows(
      repos.records.getAll().cast<Map<String, Object?>>(),
      repos.prosthetics.getAll().cast<Map<String, Object?>>(),
      repos.debts.getAll().cast<Map<String, Object?>>(),
    ).reversed.toList();
    final rowsAll = [...all, ..._todayExpenseRows(null, '').reversed];
    final rows = username.isEmpty
        ? rowsAll
        : [
            for (final r in rowsAll)
              if (r.by == username) r,
          ];
    // الصفوف غير المنسوبة (ما قبل نظام الموظفين) تُذكر صراحةً كي لا
    // تُفهم فروق التسليم خطأً على أنها عجز عند الموظف.
    final orphan = username.isEmpty
        ? 0
        : rowsAll.where((r) => r.by.isEmpty).length;
    final tot = ledgerTotals(rows);
    final n = formatNumber;
    final cfg = ref.read(appConfigProvider);
    final now = DateTime.now();
    try {
      final fonts = await loadPdfBrand(ref);
      var i = 0;
      var j = 0;
      final bytes = await shiftReportPdf(
        fonts,
        date: today,
        staffName: display,
        printedAt: '$today ${formatClock(now.millisecondsSinceEpoch)}',
        centerName: '${cfg['centerName'] ?? ''}',
        currency: '${cfg['currency'] ?? 'د.ل'}',
        incomeRows: [
          for (final r in rows)
            if (!r.isExpense)
              [
                '${++i}',
                formatClock(r.timeMs),
                r.name,
                r.clinic,
                r.kind == 'dp'
                    ? '${r.effectiveMethod.isEmpty ? r.payment : r.effectiveMethod} (${r.remaining <= 0 ? 'نهائية' : 'دفعة دين'})'
                    : r.payment,
                n(r.value),
                n(r.paid),
                n(r.remaining),
              ],
        ],
        totalPaid: n(tot.paid),
        cashPaid: n(tot.paidBy['كاش'] ?? 0),
        transferPaid: n(tot.paidBy['تحويل'] ?? 0),
        debtRemaining: n(tot.remaining),
        expenseRows: [
          for (final r in rows)
            if (r.isExpense)
              [
                '${++j}',
                formatClock(r.timeMs),
                r.name,
                r.service,
                r.effectiveMethod,
                n(r.value),
              ],
        ],
        expenseTotal: n(tot.expense),
        expenseCash: n(tot.expenseBy['كاش'] ?? 0),
        expenseTransfer: n(tot.expenseBy['تحويل'] ?? 0),
        drawerCash: n(tot.netOf('كاش')),
        drawerTransfer: n(tot.netOf('تحويل')),
        unattributedNote: orphan == 0
            ? ''
            : 'ملاحظة: باليوم ${formatNumber(orphan)} صف بلا هوية مُدخِل '
                  '(أُدخل قبل نظام الموظفين) غير مشمول بهذا التقرير.',
      );
      recordAudit(
        repos.db,
        action: 'shift.report',
        entity: 'records',
        entityId: today,
        detail: {
          'staff': username.isEmpty ? 'all' : username,
          'paid': tot.paid,
          'net': tot.net,
        },
      );
      final msg = await printOrSharePdf(
        ref.read(dbDirProvider),
        bytes,
        'shift_${username.isEmpty ? 'all' : username}_$today.pdf',
        auditDb: repos.db,
        auditEntity: 'records',
        auditId: today,
      );
      _snack(msg);
    } catch (e) {
      _snack('تعذر توليد تقرير الوردية');
    }
  }

  // ═══ م104 — قفل اليوم ═══

  bool _isTodayClosed() => DayCloseStore(
    ref.read(reposProvider).settings,
  ).isClosed(getCurrentDate());

  Future<void> _onLockTap() async {
    final today = getCurrentDate();
    final store = DayCloseStore(ref.read(reposProvider).settings);
    if (store.isClosed(today)) {
      // م119 — إعادة فتح يومٍ مقفول صلاحية مستقلة (افتراضياً للإدارة).
      if (!gateStaff(context, 'dayreopen')) return;
      // مقفول: عرض إعادة الفتح.
      final ok = await showDialog<bool>(
        context: context,
        builder: (dctx) => AlertDialog(
          title: const Text(
            'اليوم مُقفل',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          content: const Text(
            'هل تريد إعادة فتح اليوم؟ يمكنك تعديل سجلاته ثم قفله '
            'من جديد ليُنشأ تقرير ولقطة محدّثان.',
            style: TextStyle(fontSize: 13, height: 1.6),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('إبقاؤه مقفلاً'),
            ),
            FilledButton(
              key: const Key('day-reopen'),
              onPressed: () => Navigator.pop(dctx, true),
              child: const Text('إعادة فتح اليوم'),
            ),
          ],
        ),
      );
      if (ok == true && mounted) {
        store.reopen(today);
        recordAudit(
          ref.read(reposProvider).db,
          action: 'day.reopen',
          entity: 'settings',
          entityId: today,
        );
        setState(() {});
        _snack('أُعيد فتح اليوم');
      }
      return;
    }
    // غير مقفول: تحذير القفل.
    if (!gateStaff(context, 'dayclose')) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text(
          'قفل اليوم',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
        content: Text(
          'قفل يوم $today؟\n'
          '• سيُنشأ تقرير PDF بدخل اليوم لطباعته أو مشاركته.\n'
          '• بعد القفل ستُنبَّه عند أي إضافة لهذا اليوم.\n'
          '• لا تُمسح أي بيانات — الجدول يبدأ يوماً جديداً تلقائياً '
          'بعد منتصف الليل وتبقى السجلات محفوظة.',
          style: const TextStyle(fontSize: 12.5, height: 1.7),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            key: const Key('day-close-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: BrandColors.brand600,
            ),
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('قفل وطباعة'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _closeDayAndPrint(today);
  }

  /// توليد تقرير اليوم (كل اليوم بلا فلاتر) وقفله وفتح الطباعة/المشاركة.
  Future<void> _closeDayAndPrint(String today) async {
    final repos = ref.read(reposProvider);
    // م114 — التقرير بأحدث ساعة أولاً (كالشاشة).
    final all = todayLedgerRows(
      repos.records.getAll().cast<Map<String, Object?>>(),
      repos.prosthetics.getAll().cast<Map<String, Object?>>(),
      repos.debts.getAll().cast<Map<String, Object?>>(),
    ).reversed.toList();
    final rows = [...all, ..._todayExpenseRows(null, '').reversed];
    final tot = ledgerTotals(rows);
    final n = formatNumber;
    final cfg = ref.read(appConfigProvider);
    final cur = '${cfg['currency'] ?? 'د.ل'}';

    // القفل أولاً (بلقطة الإجماليات) ثم الطباعة — فلو أُلغيت الطباعة
    // يبقى اليوم مقفولاً كما طلب المستخدم صراحةً بالتأكيد.
    DayCloseStore(repos.settings).close(today, {
      'paid': tot.paid,
      'cash': tot.paidBy['كاش'] ?? 0,
      'transfer': tot.paidBy['تحويل'] ?? 0,
      'remaining': tot.remaining,
      'expense': tot.expense,
      'net': tot.net,
      'count': tot.count,
    });
    recordAudit(
      repos.db,
      action: 'day.close',
      entity: 'settings',
      entityId: today,
      detail: {'paid': tot.paid, 'net': tot.net, 'count': tot.count},
    );
    if (mounted) setState(() {});

    try {
      final fonts = await loadPdfBrand(ref);
      // م106 — التقرير الاحترافي: دخلٌ ومصروفات في جدولين منفصلين
      // بإجمالياتٍ متناظرة الأعمدة (كاش/تحويل) وصافٍ ختامي.
      var i = 0;
      final bytes = await dayClosePdf(
        fonts,
        date: today,
        centerName: '${cfg['centerName'] ?? ''}',
        currency: cur,
        incomeRows: [
          for (final r in rows)
            if (!r.isExpense)
              [
                '${++i}',
                formatClock(r.timeMs),
                r.name,
                r.clinic,
                // م115 — دفعة الدين بطريقتها الحقيقية + وسمها.
                r.kind == 'dp'
                    ? '${r.effectiveMethod.isEmpty ? r.payment : r.effectiveMethod} (${r.remaining <= 0 ? 'نهائية' : 'دفعة دين'})'
                    : r.payment,
                n(r.value),
                n(r.paid),
                n(r.remaining),
              ],
        ],
        totalPaid: n(tot.paid),
        cashPaid: n(tot.paidBy['كاش'] ?? 0),
        transferPaid: n(tot.paidBy['تحويل'] ?? 0),
        debtRemaining: n(tot.remaining),
        expenseRows: () {
          var j = 0;
          return [
            for (final r in rows)
              if (r.isExpense)
                [
                  '${++j}',
                  formatClock(r.timeMs),
                  r.name,
                  r.service,
                  r.effectiveMethod,
                  n(r.value),
                ],
          ];
        }(),
        expenseTotal: n(tot.expense),
        expenseCash: n(tot.expenseBy['كاش'] ?? 0),
        expenseTransfer: n(tot.expenseBy['تحويل'] ?? 0),
        netTotal: n(tot.net),
        netCash: n(tot.netOf('كاش')),
        netTransfer: n(tot.netOf('تحويل')),
      );
      final msg = await printOrSharePdf(
        ref.read(dbDirProvider),
        bytes,
        'day_close_$today.pdf',
        auditDb: repos.db,
        auditEntity: 'records',
        auditId: today,
      );
      if (mounted) _snack('أُقفل اليوم — $msg');
    } catch (_) {
      if (mounted) {
        _snack('أُقفل اليوم، وتعذّر إنشاء التقرير — أعد المحاولة من زر القفل');
      }
    }
  }

  Widget _activeChips() {
    Widget chip(String label, VoidCallback onClear) => Padding(
      padding: const EdgeInsets.only(left: 6),
      child: InputChip(
        label: Text(label, style: const TextStyle(fontSize: 11.5)),
        onDeleted: onClear,
        visualDensity: VisualDensity.compact,
        backgroundColor: BrandColors.surface,
      ),
    );
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final c in _clinics)
            chip(c, () => setState(() => _clinics.remove(c))),
          for (final p in _payments)
            chip(p, () => setState(() => _payments.remove(p))),
          if (_onlyRemaining)
            chip('عليه متبقٍّ', () => setState(() => _onlyRemaining = false)),
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: TextButton(
              onPressed: () => setState(() {
                _clinics.clear();
                _payments.clear();
                _onlyRemaining = false;
              }),
              child: const Text('مسح', style: TextStyle(fontSize: 11.5)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openFilter(
    List<String> clinicOpts,
    List<String> payOpts,
  ) async {
    // نسخ محلية تُطبَّق عند الضغط.
    final clinics = {..._clinics};
    final payments = {..._payments};
    var onlyRem = _onlyRemaining;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: BrandColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setLocal) {
          Widget section(String title, List<String> opts, Set<String> sel) =>
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 4),
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: BrandColors.brandText,
                      ),
                    ),
                  ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final o in opts)
                        FilterChip(
                          label: Text(o, style: const TextStyle(fontSize: 12)),
                          selected: sel.contains(o),
                          onSelected: (v) =>
                              setLocal(() => v ? sel.add(o) : sel.remove(o)),
                        ),
                    ],
                  ),
                ],
              );
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Text(
                    'فلترة دخل اليوم',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: BrandColors.brandText,
                    ),
                  ),
                ),
                if (clinicOpts.isNotEmpty)
                  section('العيادة', clinicOpts, clinics),
                if (payOpts.isNotEmpty)
                  section('طريقة الدفع', payOpts, payments),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text(
                    'عليه متبقٍّ فقط',
                    style: TextStyle(fontSize: 12.5),
                  ),
                  value: onlyRem,
                  onChanged: (v) => setLocal(() => onlyRem = v),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => setLocal(() {
                          clinics.clear();
                          payments.clear();
                          onlyRem = false;
                        }),
                        child: const Text('مسح الكل'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        key: const Key('daily-filter-apply'),
                        onPressed: () => Navigator.pop(sheetCtx),
                        child: const Text('تطبيق'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
    setState(() {
      _clinics
        ..clear()
        ..addAll(clinics);
      _payments
        ..clear()
        ..addAll(payments);
      _onlyRemaining = onlyRem;
    });
  }

  Widget _empty(String title, String sub) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_long_rounded, size: 48, color: BrandColors.faint),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: BrandColors.brandText,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            sub,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: BrandColors.mut),
          ),
        ],
      ),
    ),
  );
}

/// زر أداة بشارة عدد (للفلترة).
class _ToolBtn extends StatelessWidget {
  const _ToolBtn({
    super.key,
    required this.icon,
    required this.badge,
    required this.onTap,
  });
  final IconData icon;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          _ToolBtnShell(child: Icon(icon)),
          if (badge > 0)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: BrandColors.gold,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$badge',
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    color: BrandColors.brand900,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ToolBtnShell extends StatelessWidget {
  const _ToolBtnShell({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: BrandColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: BrandColors.line),
      ),
      child: IconTheme(
        data: const IconThemeData(size: 20, color: BrandColors.brand),
        child: child,
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.date,
    required this.tot,
    required this.cur,
    this.showExpenses = false,
    this.closed = false,
  });
  final String date;
  final LedgerTotals tot;
  final String cur;
  final bool showExpenses;

  /// م104 — اليوم مُقفل (شارة في سطر العنوان).
  final bool closed;

  @override
  Widget build(BuildContext context) {
    final n = formatNumber;
    // م95 — خانات تتحمل 4 أعمدة بصفٍّ واحد: التسمية سطرٌ واحد،
    // والقيمة تنكمش بدل الفيضان (FittedBox).
    Widget stat(String label, String value, Color color) => Expanded(
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(fontSize: 10, color: BrandColors.goldLight),
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: BrandColors.brandGradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.today_rounded,
                color: BrandColors.goldLight,
                size: 18,
              ),
              const SizedBox(width: 8),
              // م133 — العنوان كان نصاً صلباً فيفيض الصف 251ن بأقصى
              // مقياس خط (كشفه m41): يُحمى بنمط م95 نفسه المطبق على
              // خانات هذه البطاقة — انكماشٌ بدل الفيضان، وسطرٌ واحد.
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'دخل اليوم • ${appDigits(date)}',
                      maxLines: 1,
                      style: const TextStyle(
                        color: BrandColors.goldLight,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (closed) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color.fromRGBO(201, 162, 75, .25),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.lock_rounded,
                        size: 12,
                        color: BrandColors.goldLight,
                      ),
                      SizedBox(width: 3),
                      Text(
                        'مُقفل',
                        style: TextStyle(
                          color: BrandColors.goldLight,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                '${tot.count} حالة',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // ── م95: الصف الدائم — الإجمالي (المدفوع) | كاش | تحويل | الدين ──
          // م99: مع «المصروفات» تُخفى خانة الدين ديناميكياً فتتوازى
          // الصفوف الثلاثة بثلاثة أعمدة تماماً (إجمالي | كاش | تحويل).
          Row(
            children: [
              stat(
                'الإجمالي (المدفوع)',
                '${n(tot.paid)} $cur',
                const Color(0xFF7BE3AE),
              ),
              stat('كاش', n(tot.paidBy['كاش'] ?? 0), Colors.white),
              stat('تحويل', n(tot.paidBy['تحويل'] ?? 0), Colors.white),
              if (!showExpenses)
                stat(
                  'الدين',
                  n(tot.remaining),
                  tot.remaining > 0 ? const Color(0xFFF6B4B4) : Colors.white,
                ),
            ],
          ),
          if (showExpenses) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Divider(
                height: 1,
                color: Color.fromRGBO(255, 255, 255, .18),
              ),
            ),
            // ── صف المصروف: الإجمالي | مصروف كاش | مصروف تحويل ──
            Row(
              children: [
                stat('المصروف', n(tot.expense), const Color(0xFFF6B4B4)),
                stat(
                  'مصروف كاش',
                  n(tot.expenseBy['كاش'] ?? 0),
                  const Color(0xFFF6B4B4),
                ),
                stat(
                  'مصروف تحويل',
                  n(tot.expenseBy['تحويل'] ?? 0),
                  const Color(0xFFF6B4B4),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // ── صف الصافي بعد خصم المصروف: الإجمالي | كاش | تحويل ──
            Row(
              children: [
                stat('الصافي (بعد الخصم)', '${n(tot.net)} $cur', Colors.white),
                stat('صافي كاش', n(tot.netOf('كاش')), Colors.white),
                stat('صافي تحويل', n(tot.netOf('تحويل')), Colors.white),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// جدول يملأ عرض الشاشة (أعمدة بأوزان مرنة، بلا تمرير أفقي) برأسٍ ثابت
/// أعلاه والصفوف تُمرَّر رأسياً وحدها.
class _LedgerTable extends StatelessWidget {
  const _LedgerTable({required this.rows, this.onRowMenu});
  final List<LedgerRow> rows;

  /// م99 — ضغط مطول/نقر يميني على صف ⇒ قائمة خيارات.
  final void Function(LedgerRow row)? onRowMenu;

  @override
  Widget build(BuildContext context) {
    final n = formatNumber;
    // ترقيم الحالات — يتخطّى صفوف المصروف.
    final seqs = <String>[];
    var s = 0;
    for (final r in rows) {
      if (r.isExpense) {
        seqs.add('—');
      } else {
        s++;
        seqs.add('$s');
      }
    }
    return Column(
      children: [
        const _HeaderRow(),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: rows.length,
            itemBuilder: (_, i) => _LedgerRowTile(
              row: rows[i],
              seq: seqs[i],
              n: n,
              onMenu: onRowMenu,
            ),
          ),
        ),
      ],
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    Widget h(String s, int flex, {TextAlign a = TextAlign.center}) => Expanded(
      flex: flex,
      child: Text(
        s,
        textAlign: a,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: BrandColors.goldLight,
          fontWeight: FontWeight.w800,
          fontSize: 10.5,
        ),
      ),
    );
    return Container(
      color: BrandColors.brand,
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
      child: Row(
        children: [
          h('#', _fxNum),
          h('الساعة', _fxTime),
          h('الاسم', _fxName, a: TextAlign.start),
          h('العيادة', _fxClinic, a: TextAlign.start),
          h('الدفع', _fxPay),
          h('القيمة', _fxVal),
          h('المدفوع', _fxPaid),
          h('المتبقي', _fxRem),
        ],
      ),
    );
  }
}

class _LedgerRowTile extends StatelessWidget {
  const _LedgerRowTile({
    required this.row,
    required this.seq,
    required this.n,
    this.onMenu,
  });
  final LedgerRow row;
  final String seq;
  final String Function(num) n;

  /// م99 — ضغط مطول (وباللاقط الثانوي: النقر اليميني للفأرة).
  final void Function(LedgerRow row)? onMenu;

  @override
  Widget build(BuildContext context) {
    final exp = row.isExpense;
    Widget txt(
      String s,
      int flex, {
      Color? c,
      FontWeight? w,
      bool tnum = false,
      TextAlign a = TextAlign.center,
    }) => Expanded(
      flex: flex,
      child: Text(
        s,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: a,
        style: TextStyle(
          fontSize: 10.8,
          height: 1.1,
          color: c ?? BrandColors.ink,
          fontWeight: w,
          fontFeatures: tnum ? const [FontFeature.tabularFigures()] : null,
        ),
      ),
    );
    return GestureDetector(
      // م99 — قائمة الخيارات: ضغط مطول على الهاتف، نقر يميني بالفأرة.
      onLongPress: onMenu == null ? null : () => onMenu!(row),
      onSecondaryTapUp: onMenu == null ? null : (_) => onMenu!(row),
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: BoxDecoration(
          color: exp ? const Color.fromRGBO(192, 57, 43, .06) : null,
          border: const Border(
            bottom: BorderSide(color: Color(0x11000000), width: .5),
          ),
        ),
        // م-تحسين (بلاغ المالك) — صف الدفع المختلط أعلى قليلاً ليتنفّس
        // سطرا الكاش والتحويل بوضوح (padding رأسيّ أكبر عند الخلط).
        padding: EdgeInsets.symmetric(
            vertical: row.isMixedPay ? 13 : 9, horizontal: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            txt(seq, _fxNum, tnum: true),
            txt(formatClock(row.timeMs), _fxTime, tnum: true),
            txt(
              row.name,
              _fxName,
              w: FontWeight.w700,
              a: TextAlign.start,
              c: exp ? BrandColors.red : BrandColors.brandText,
            ),
            txt(row.clinic, _fxClinic, a: TextAlign.start, c: BrandColors.mut),
            Expanded(
              flex: _fxPay,
              child: Center(
                // م115 — دفعة الدين: الرقاقة بطريقة الدفع الحقيقية
                // (كاش/تحويل) وتحتها سطرٌ صغير «دفعة دين» — أو «دفعة
                // نهائية» متى صفّرت الدفعةُ الدينَ (طلب المالك).
                // م-تكافؤ — الدفع المختلط (كاش+تحويل معاً): الطرق
                // رأسياً بخط أصغر + أيقونة معلومات تفصّل القيم.
                child: row.isMixedPay
                    ? MixedPayCell(row: row)
                    : row.kind == 'dp'
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: _PayChip(
                              row.effectiveMethod.isEmpty
                                  ? row.payment
                                  : row.effectiveMethod,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            row.remaining <= 0 ? 'دفعة نهائية' : 'دفعة دين',
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 7.5,
                              fontWeight: FontWeight.w700,
                              color: BrandColors.mut2,
                            ),
                          ),
                        ],
                      )
                    : FittedBox(
                        fit: BoxFit.scaleDown,
                        child: _PayChip(row.payment),
                      ),
              ),
            ),
            exp
                ? txt(
                    '- ${n(row.value)}',
                    _fxVal,
                    c: BrandColors.red,
                    w: FontWeight.w800,
                    tnum: true,
                  )
                : txt(n(row.value), _fxVal, w: FontWeight.w800, tnum: true),
            exp
                ? txt('—', _fxPaid)
                : txt(
                    n(row.paid),
                    _fxPaid,
                    c: BrandColors.green,
                    w: FontWeight.w700,
                    tnum: true,
                  ),
            exp
                ? txt('—', _fxRem)
                : txt(
                    n(row.remaining),
                    _fxRem,
                    c: row.remaining > 0 ? BrandColors.red : BrandColors.mut,
                    w: FontWeight.w700,
                    tnum: true,
                  ),
          ],
        ),
      ),
    );
  }
}

class _PayChip extends StatelessWidget {
  const _PayChip(this.payment);
  final String payment;

  @override
  Widget build(BuildContext context) {
    final isDebt = payment == 'دين';
    final isDebtPay = payment == 'دفعة دين';
    final isExpense = payment == 'مصروف';
    final bg = (isDebt || isExpense)
        ? const Color.fromRGBO(192, 57, 43, .10)
        : isDebtPay
        ? const Color.fromRGBO(184, 134, 11, .12)
        : const Color.fromRGBO(30, 122, 82, .10);
    final fg = (isDebt || isExpense)
        ? BrandColors.red
        : isDebtPay
        ? BrandColors.goldDark
        : BrandColors.green;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        payment.isEmpty ? '—' : payment,
        maxLines: 1,
        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: fg),
      ),
    );
  }
}
