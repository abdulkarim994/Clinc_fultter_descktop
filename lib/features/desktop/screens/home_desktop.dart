/// ============================================================================
///  الرئيسية — نسخة سطح المكتب: لوحة ودجات + جدول الدخل اليومي الاحترافي
/// ============================================================================
///
///  (قرار المالك — «ثانياً: الشاشة الرئيسية»):
///  - جدول الإدخال اليومي بأعمدة: رقم · الساعة · الاسم · العيادة ·
///    **نوع العلاج قبل طريقة الدفع** · القيمة · المدفوع · المتبقي ·
///    **ملاحظات مختصرة** (نسخة الكمبيوتر فقط — يعرض حقل notes الموجود) ·
///    المُدخِل — مع فرز وإخفاء/إظهار وتغيير عرض وتثبيت أعمدة وتحديد
///    متعدد (كلها من عدة DesktopDataTable).
///  - وسم الصفوف بخمسة ألوان محفوظة (desktopRowTags المتزامن).
///  - اللوحة العلوية ودجات إحصاء **متجاورة** يمكن تغيير مكان كلٍّ منها
///    بالسحب، والترتيب محفوظ محلياً.
///
///  البيانات ومنطق العمل مشتركان 1:1 مع الهاتف (home_logic.dart) —
///  وتدفقات «تقرير الوردية/قفل اليوم/الحذف/التعديل» توائم حرفية لتدفقات
///  DailyIncomeScreen (م99/م104/م117/م119/م120) بنفس البوابات والتواقيع
///  والتدقيق، مع الإشارة لكل توأم في موضعه.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/display_prefs.dart'
    show appDigits, formatClock, kPeriodCutoffHour;
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/js_compat.dart' show getCurrentDate;
import '../../../core/widgets/double_confirm.dart' show confirmDelete;
import '../../../data/audit/audit_trail.dart' show recordAudit;
import '../../expenses/expenses_report.dart'
    show expenseCategoryLabel, expenseIsCash;
import '../../expenses/expenses_screen.dart' show expensesRefreshProvider;
import '../../finance/finance_screen.dart' show financeRevProvider;
import '../../patients/patient_profile_screen.dart' show PatientProfileScreen;
import '../../patients/patients_tab.dart' show patientsRevProvider;
import '../../patients/profile_actions.dart' show deleteEntryCascade;
import '../../patients/quick_info_dialog.dart' show showQuickInfoDialog;
import '../../patients/quick_visit_sheet.dart' show showQuickVisitSheet;
import '../../print/print_service.dart' show loadPdfBrand, printOrSharePdf;
import '../../print/reports.dart' show dayClosePdf, shiftReportPdf;
import '../../print/treatment_tables.dart' show formatNumber;
import '../../records/add_record_screen.dart' show openAddRecordSheet;
import '../../records/analysis_actions.dart' show promptAddAnalysisToVisit;
import '../../records/day_close_store.dart'
    show DayCloseStore, confirmClosedDayWrite;
import '../../records/home_logic.dart' hide JMap;
import '../../records/pay_breakdown_dialog.dart' show MixedPayCell;
// م168 — حارسا الرؤية المركزيان للتحاليل الثلاثية (اختفاء شامل عند الإيقاف).
import '../../settings/analyses3.dart'
    show triAnalysesEnabled, triVisibleOnDate;
import '../../staff/staff_gate.dart'
    show gateStaff, requestAdminSignature, staffAllowed;
import '../../staff/staff_session.dart' show kCurrentStaff, staffIsAdmin;
import '../../staff/staff_store.dart' show StaffStore;
import '../desktop_prefs.dart';
import '../widgets/context_menu.dart';
import '../widgets/desktop_dialogs.dart';
import '../widgets/desktop_table.dart';
import '../widgets/split_view.dart' show DetailHost;

class DesktopHomeScreen extends ConsumerStatefulWidget {
  const DesktopHomeScreen({super.key});

  @override
  ConsumerState<DesktopHomeScreen> createState() => _DesktopHomeScreenState();
}

/// نظام «التحاليل» — فلتر ما-بعد على صفوف الجدول حسب حالة تحليلها.
/// م151 — [totals] «إجمالي التحاليل»: كل أصحاب التحاليل بأي طريقة.
enum _AnalFilter { all, cash, transfer, totals, none }

const _analFilterLabels = <_AnalFilter, String>{
  _AnalFilter.all: 'الكل',
  _AnalFilter.cash: 'تحاليل كاش',
  _AnalFilter.transfer: 'تحاليل تحويل',
  _AnalFilter.totals: 'إجمالي التحاليل',
  _AnalFilter.none: 'بلا تحاليل',
};

class _DesktopHomeScreenState extends ConsumerState<DesktopHomeScreen> {
  final Set<String> _clinics = {};
  final Set<String> _payments = {};
  bool _onlyRemaining = false;
  LedgerPeriod? _period;
  bool _showExpenses = false;

  /// نظام «التحاليل» — فلتر التحاليل (ما-بعد فوق filterLedgerRows النقية).
  _AnalFilter _analFilter = _AnalFilter.all;

  final _tableCtl = DeskTableController<LedgerRow>();

  @override
  void dispose() {
    _tableCtl.dispose();
    super.dispose();
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), duration: const Duration(milliseconds: 1600)),
  );

  /// م120 — توأم _staffDisplay: الاسم الظاهر لموظف من اسم دخوله.
  String _staffDisplay(String username) {
    final u = StaffStore(ref.read(reposProvider).settings).byUsername(username);
    return u == null ? username : '${u['name']}';
  }

  // ── البيانات (نفس مسار الهاتف حرفياً) ──

  /// توأم _todayExpenseRows في DailyIncomeScreen (بلا فلتر البحث —
  /// البحث الفوري من عدة الجدول).
  List<LedgerRow> _todayExpenseRows(LedgerPeriod? period) {
    final repos = ref.read(reposProvider);
    final today = getCurrentDate();
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

  bool _isTodayClosed() => DayCloseStore(
    ref.read(reposProvider).settings,
  ).isClosed(getCurrentDate());

  // ── البناء ──

  @override
  Widget build(BuildContext context) {
    ref.watch(patientsRevProvider);
    ref.watch(expensesRefreshProvider);
    // م-إصلاح — تراقب النبض المالي أيضاً: تعديل دفعة/دين (ينبض financeRev)
    // يعيد بناء جدول الرئيسية فوراً بدل انتظار تبديل التبويب (بلاغ المالك).
    ref.watch(financeRevProvider);
    final repos = ref.watch(reposProvider);
    final cur = ref.watch(currencyProvider);
    final tags = ref.watch(rowTagsProvider);

    final records = repos.records.getAll().cast<Map<String, Object?>>();
    final pros = repos.prosthetics.getAll().cast<Map<String, Object?>>();
    final debts = repos.debts.getAll().cast<Map<String, Object?>>();

    final all = todayLedgerRows(records, pros, debts);
    final clinicOpts = (<String>{for (final r in all) r.clinic}.toList())
      ..sort();
    // م-تكافؤ — خيارات الدفع الموحّدة (تشمل طرق الأجزاء المختلطة).
    final payOpts = ledgerPayOptions(all);

    // نظام «التحاليل» — فهرس ربط الصفوف بتحاليلها (عرضاً فقط؛ صفوف
    // التحاليل محروسةٌ خارج الجدول والمالية). يُبنى من كل السجلات مباشرة.
    final analIndex = buildAnalysisIndex(records);
    final today = getCurrentDate();
    // م168 — رؤية التحاليل مركزياً: عمود «التحاليل» وفلترها يظهران حتى
    // يوم الإيقاف (عرض تاريخي) ويختفيان كلياً بعده؛ ومع الإخفاء يُعامل
    // الفلتر كأنه «الكل» فلا تُحجب صفوفٌ بحالةٍ قديمةٍ عالقة.
    final triSee = triVisibleOnDate(ref.watch(appConfigProvider), today);
    final effAnalFilter = triSee ? _analFilter : _AnalFilter.all;
    // م151 — كل تحليلٍ يُنسب لصفٍّ **واحد** بالضبط (المرتبط بمعرّفه، والقديم
    // بلا ربطٍ على أقدم صفوف مريضه): ✓ واحدة لكل مريضٍ أجرى التحليل لا لكل
    // صفوفه. تُبنى من صفوف اليوم كلها فلا تقفز العلامة مع تبديل الفلاتر.
    final analMarks = analysisRowMarks(all, analIndex, today);
    List<AnalysisLink> analOf(LedgerRow r) =>
        analMarks[r.id] ?? const <AnalysisLink>[];

    final filtered = filterLedgerRows(
      all,
      nameQuery: '',
      clinics: _clinics,
      payments: _payments,
      onlyRemaining: _onlyRemaining,
      period: _period,
      cutoffHour: kPeriodCutoffHour,
    );
    // نظام «التحاليل» — فلتر ما-بعد فوق الدالة النقية (لا تُعدَّل هي).
    // م168 — عبر effAnalFilter (يؤول إلى «الكل» عند إخفاء الميزة).
    bool analOk(LedgerRow r) {
      if (effAnalFilter == _AnalFilter.all) return true;
      final links = analOf(r);
      switch (effAnalFilter) {
        case _AnalFilter.none:
          return links.isEmpty;
        case _AnalFilter.cash:
          return links.any((a) => a.isCash);
        case _AnalFilter.transfer:
          return links.any((a) => !a.isCash);
        case _AnalFilter.totals:
          return links.isNotEmpty;
        case _AnalFilter.all:
          return true;
      }
    }

    final income = [
      for (final r in filtered)
        if (analOk(r)) r,
    ];
    final expenseRows = _showExpenses
        ? _todayExpenseRows(_period)
        : const <LedgerRow>[];
    final rows = [...income, ...expenseRows];
    // م151 — الحساب المالي للتحاليل من صفوفها المستقلة حصراً (منع تكرار
    // بالمعرّف)، بنفس فلاتر الشاشة: العيادة/طريقة الدفع/الفترة — فيُعاد
    // الحساب فوراً مع كل تغيير. علامات ✓ وعدد الصفوف ليسا مصدراً أبداً.
    final anal = dayAnalysesTotals(
      records,
      clinics: _clinics,
      payments: _payments,
      period: _period,
      cutoffHour: kPeriodCutoffHour,
    );
    final tot0 = ledgerTotals(rows);
    // خانات المال حسب وضع فلتر التحاليل (مواصفة المالك م151):
    //  «الكل» = الإيراد + التحاليل مرةً واحدة؛ «تحاليل كاش/تحويل/إجمالي
    //  التحاليل» = قيم التحاليل وحدها؛ «بلا تحاليل» = الإيراد العادي فقط.
    // م168 — عبر effAnalFilter: عند الإخفاء يبقى الحساب على وضع «الكل»
    // (الإيراد + التحاليل مرةً واحدة) فلا يتغير أي إجمالي مالي.
    final tot = switch (effAnalFilter) {
      _AnalFilter.all => totalsWithAnalyses(tot0, anal),
      _AnalFilter.none => tot0,
      _AnalFilter.cash =>
        analysesOnlyTotals(tot0, (cash: anal.cash, transfer: 0)),
      _AnalFilter.transfer =>
        analysesOnlyTotals(tot0, (cash: 0, transfer: anal.transfer)),
      _AnalFilter.totals => analysesOnlyTotals(tot0, anal),
    };

    // «ملاحظات مختصرة» — حقل notes الموجود على السجل/التركيبة/المصروف.
    final notes = <String, String>{};
    for (final r in records) {
      final n = '${r['notes'] ?? ''}'.trim();
      if (n.isNotEmpty && n != 'null') notes['r:${r['id']}'] = n;
    }
    for (final p in pros) {
      final n = '${p['notes'] ?? ''}'.trim();
      if (n.isNotEmpty && n != 'null') notes['p:${p['id']}'] = n;
    }
    for (final e in repos.expenses.getByDay(getCurrentDate())) {
      final n = '${e['note'] ?? e['notes'] ?? ''}'.trim();
      if (n.isNotEmpty && n != 'null') notes['e:${e['id']}'] = n;
    }

    // ترقيم ثابت بترتيب التسجيل (كترقيم الهاتف/التقارير) مهما تغير الفرز.
    final serial = <String, int>{};
    final byTime = [for (final r in income) r]
      ..sort((a, b) => a.timeMs.compareTo(b.timeMs));
    for (var i = 0; i < byTime.length; i++) {
      serial[_rowKey(byTime[i])] = i + 1;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DeskDashboard(
          tot: tot,
          cur: cur,
          date: getCurrentDate(),
          closed: _isTodayClosed(),
          showExpenses: _showExpenses,
        ),
        Expanded(
          child: DesktopDataTable<LedgerRow>(
            tableId: 'home.ledger',
            controller: _tableCtl,
            rows: rows,
            rowId: _rowKey,
            searchText: (r) => '${r.name} ${r.clinic} ${r.service}',
            searchHint: 'بحث بالاسم…',
            defaultSortId: 'time',
            defaultSortAsc: false,
            // م-تكافؤ — كالهاتف: يفتح دائماً على الأحدث أولاً (الفرز
            // داخل الجلسة فقط، لا يُحفظ بين الفتحات).
            persistSort: false,
            // م-تحسين (بلاغ المالك) — صف أعلى قليلاً ليتنفّس سطرا الكاش
            // والتحويل في صفوف الدفع المختلط (الجدول مُوحَّد الارتفاع).
            rowHeight: 46,
            defaultPinned: const ['name'],
            emptyTitle: all.isEmpty ? 'لا دخل مسجّل اليوم' : 'لا نتائج مطابقة',
            emptyHint: all.isEmpty
                ? 'اضغط «زيارة جديدة» أو Ctrl+N لإضافة زيارة أو دفعة.'
                : 'جرّب تعديل البحث أو الفلاتر.',
            // م168 — تمرير رؤية التحاليل لشريط الفلاتر (إخفاء فلترها).
            toolbarLeading: _filtersBar(clinicOpts, payOpts, triSee),
            toolbarTrailing: _dayActions(),
            rowTagOf: (r) => tags[_rowKey(r)],
            onTagRows: (list, tag) =>
                setRowTags(ref, [for (final r in list) _rowKey(r)], tag),
            onOpen: _openProfile,
            onDelete: (list) {
              if (list.length > 1) {
                _snack('الحذف الجماعي غير مدعوم — احذف صفاً صفاً');
                return;
              }
              _deleteRow(list.first);
            },
            contextMenuOf: (r) => _rowMenu(r, tags[_rowKey(r)], analOf),
            selectionActions: (sel) => [
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(
                    ClipboardData(
                      text: [for (final r in sel) r.name].join('\n'),
                    ),
                  );
                  _snack('نُسخت ${sel.length} أسماء');
                },
                icon: const Icon(Icons.copy_rounded, size: 15),
                label: const Text(
                  'نسخ الأسماء',
                  style: TextStyle(fontSize: 11.5),
                ),
              ),
            ],
            columns: [
              DeskCol<LedgerRow>(
                id: 'num',
                label: 'رقم',
                width: 52,
                minWidth: 40,
                numeric: true,
                sortKey: (r) => serial[_rowKey(r)] ?? 1 << 20,
                cell: (_, r) => Text(
                  r.isExpense ? 'م' : '${serial[_rowKey(r)] ?? '—'}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: r.isExpense ? BrandColors.red : BrandColors.mut2,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              DeskCol<LedgerRow>(
                id: 'time',
                label: 'الساعة',
                width: 86,
                minWidth: 64,
                numeric: true,
                sortKey: (r) => r.timeMs,
                cell: (_, r) => Text(
                  formatClock(r.timeMs),
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    fontSize: 12,
                    color: BrandColors.mut,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              DeskCol<LedgerRow>(
                id: 'name',
                label: 'الاسم',
                width: 190,
                minWidth: 120,
                flex: 2,
                sortKey: (r) => r.name,
                cell: (_, r) => Text(
                  r.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: r.isExpense
                        ? BrandColors.red
                        : BrandColors.brandText,
                  ),
                ),
              ),
              DeskCol.text<LedgerRow>(
                id: 'clinic',
                label: 'العيادة',
                width: 120,
                value: (r) => r.clinic,
              ),
              // (قرار المالك) نوع العلاج **قبل** طريقة الدفع.
              DeskCol.text<LedgerRow>(
                id: 'service',
                label: 'نوع العلاج',
                width: 170,
                flex: 1,
                value: (r) => r.service,
              ),
              DeskCol<LedgerRow>(
                id: 'payment',
                label: 'الدفع',
                width: 108,
                minWidth: 80,
                sortKey: (r) => r.payment,
                // م-تكافؤ — المختلط: الطرق رأسياً + أيقونة التفاصيل.
                cell: (_, r) => r.isMixedPay
                    ? MixedPayCell(row: r, compact: false)
                    : _PayChip(row: r),
              ),
              DeskCol<LedgerRow>(
                id: 'value',
                label: 'القيمة',
                width: 96,
                minWidth: 72,
                numeric: true,
                sortKey: (r) => r.value,
                cell: (_, r) => _money(
                  r.value,
                  color: r.isExpense ? BrandColors.red : BrandColors.ink,
                ),
              ),
              DeskCol<LedgerRow>(
                id: 'paid',
                label: 'المدفوع',
                width: 96,
                minWidth: 72,
                numeric: true,
                sortKey: (r) => r.paid,
                cell: (_, r) => r.isExpense
                    ? const Text('—')
                    : _money(r.paid, color: BrandColors.green),
              ),
              DeskCol<LedgerRow>(
                id: 'remaining',
                label: 'المتبقي',
                width: 96,
                minWidth: 72,
                numeric: true,
                sortKey: (r) => r.remaining,
                cell: (_, r) => r.isExpense || r.remaining <= 0
                    ? Text(
                        '—',
                        style: TextStyle(
                          fontSize: 12,
                          color: BrandColors.faint,
                        ),
                      )
                    : _money(r.remaining, color: BrandColors.red),
              ),
              // نظام «التحاليل» — عمودٌ بين «المتبقي» و«معلومات مختصرة»:
              // علامة صحٍّ (بلا أي قيمةٍ مالية) خضراء للكاش وذهبية للتحويل،
              // وتلميحٌ بالاسم/القيمة/الطريقة. غير قابلٍ للفرز.
              // م168 — يختفي العمود كلياً عند إخفاء الميزة (triSee) —
              // والجدول يعيد توزيع أعمدته تلقائياً بلا فراغ.
              if (triSee)
              DeskCol<LedgerRow>(
                id: 'analysis',
                label: 'التحاليل',
                width: 92,
                minWidth: 70,
                sortable: false,
                cell: (_, r) {
                  // المواصفة — الخلية تبقى فارغة بلا تحليل.
                  if (r.isExpense) return const SizedBox.shrink();
                  final links = analOf(r);
                  // المواصفة — الخلية تبقى فارغة بلا تحليل.
                  if (links.isEmpty) return const SizedBox.shrink();
                  final hasCash = links.any((a) => a.isCash);
                  // خضراء متى وُجد كاشٌ، وإلا ذهبية (تحويلٌ فقط).
                  final color = hasCash
                      ? BrandColors.green
                      : const Color(0xFF8A6D1B);
                  final tip = links
                      .map(
                        (a) =>
                            '${a.name}: ${formatNumber(a.amount)} (${a.payment})',
                      )
                      .join('\n');
                  return Tooltip(
                    message: tip,
                    waitDuration: const Duration(milliseconds: 400),
                    child: Icon(
                      Icons.check_circle_rounded,
                      size: 18,
                      color: color,
                    ),
                  );
                },
              ),
              // (قرار المالك) «معلومات مختصرة» — الاسم موحّد عبر المنصات.
              DeskCol<LedgerRow>(
                id: 'notes',
                label: 'معلومات مختصرة',
                width: 200,
                minWidth: 100,
                flex: 2,
                sortable: false,
                cell: (_, r) {
                  // دفعة الدين (dp) صفُّ سجلٍ في المستودع ⇒ مفتاحها r:.
                  final n =
                      notes['${r.kind == 'dp' ? 'r' : r.kind}:${r.id}'] ?? '';
                  if (n.isEmpty) {
                    return Text(
                      '—',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: BrandColors.faint2,
                      ),
                    );
                  }
                  return Tooltip(
                    message: n,
                    waitDuration: const Duration(milliseconds: 500),
                    child: Text(
                      n,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: BrandColors.mut),
                    ),
                  );
                },
              ),
              // (قرار المالك) عمود «المُدخِل» أُزيل نهائياً — غير مستخدم.
              // بيانات created_by تبقى في قاعدة البيانات للتدقيق؛ الحذف عرضيّ.
            ],
          ),
        ),
      ],
    );
  }

  static String _rowKey(LedgerRow r) =>
      '${r.kind}:${r.id.isEmpty ? '${r.name}|${r.timeMs}' : r.id}';

  static Widget _money(num v, {required Color color}) => Text(
    formatNumber(v),
    textDirection: TextDirection.ltr,
    style: TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w800,
      color: color,
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
  );

  // ── شريط الفلاتر (توأم فلاتر الهاتف بمظهر مكتبي مضغوط) ──

  Widget _filtersBar(
      List<String> clinicOpts, List<String> payOpts, bool triSee) {
    Widget seg(String label, LedgerPeriod? p) {
      final on = _period == p;
      return Padding(
        padding: const EdgeInsetsDirectional.only(end: 4),
        child: ChoiceChip(
          label: Text(label, style: const TextStyle(fontSize: 11)),
          selected: on,
          visualDensity: VisualDensity.compact,
          onSelected: (_) => setState(() => _period = p),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          seg('كل اليوم', null),
          seg('صباحي', LedgerPeriod.morning),
          seg('مسائي', LedgerPeriod.evening),
          const SizedBox(width: 6),
          _MultiFilter(
            label: 'العيادة',
            options: clinicOpts,
            selected: _clinics,
            onChanged: () => setState(() {}),
          ),
          const SizedBox(width: 4),
          _MultiFilter(
            label: 'الدفع',
            options: payOpts,
            selected: _payments,
            onChanged: () => setState(() {}),
          ),
          const SizedBox(width: 6),
          FilterChip(
            label: const Text('المتبقي فقط', style: TextStyle(fontSize: 11)),
            selected: _onlyRemaining,
            visualDensity: VisualDensity.compact,
            onSelected: (v) => setState(() => _onlyRemaining = v),
          ),
          const SizedBox(width: 4),
          // نظام «التحاليل» — مجموعة فلتر التحاليل (جميع/كاش/تحويل/بدون).
          // م168 — تختفي كلياً بفاصلها (بلا مساحة) عند إخفاء الميزة.
          if (triSee) ...[
          PopupMenuButton<_AnalFilter>(
            key: const Key('desk-anal-filter'),
            tooltip: 'فلتر التحاليل',
            onSelected: (v) => setState(() => _analFilter = v),
            itemBuilder: (context) => [
              for (final f in _AnalFilter.values)
                CheckedPopupMenuItem(
                  key: Key('desk-anal-filter-${f.name}'),
                  value: f,
                  checked: _analFilter == f,
                  child: Text(
                    '${_analFilterLabels[f]}',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
            ],
            child: Chip(
              avatar: Icon(
                Icons.science_rounded,
                size: 14,
                color: _analFilter == _AnalFilter.all
                    ? BrandColors.mut
                    : BrandColors.green,
              ),
              label: Text(
                _analFilter == _AnalFilter.all
                    ? 'التحاليل'
                    : '${_analFilterLabels[_analFilter]}',
                style: const TextStyle(fontSize: 11),
              ),
              visualDensity: VisualDensity.compact,
              backgroundColor: _analFilter == _AnalFilter.all
                  ? null
                  : BrandColors.green.withValues(alpha: .12),
            ),
          ),
          const SizedBox(width: 4),
          ],
          FilterChip(
            key: const Key('desk-expenses-toggle'),
            avatar: Icon(
              Icons.receipt_long_rounded,
              size: 14,
              color: _showExpenses ? Colors.white : BrandColors.mut,
            ),
            label: const Text('المصروفات', style: TextStyle(fontSize: 11)),
            selected: _showExpenses,
            selectedColor: BrandColors.red,
            labelStyle: TextStyle(
              color: _showExpenses ? Colors.white : BrandColors.ink,
              fontWeight: FontWeight.w700,
            ),
            visualDensity: VisualDensity.compact,
            onSelected: (v) => setState(() => _showExpenses = v),
          ),
        ],
      ),
    );
  }

  // أزرار اليوم: تقرير الوردية + قفل/فتح اليوم (توأم أدوات الهاتف).
  Widget _dayActions() {
    Widget btn({
      required Key key,
      required IconData icon,
      required String tip,
      required VoidCallback onTap,
      Color? color,
    }) => Tooltip(
      message: tip,
      child: InkWell(
        key: key,
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: BrandColors.surface2,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: BrandColors.line),
          ),
          child: Icon(icon, size: 17, color: color ?? BrandColors.brandIcon),
        ),
      ),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (staffAllowed('print'))
          btn(
            key: const Key('desk-shift-report'),
            icon: Icons.assignment_ind_rounded,
            tip: 'تقرير تسليم الوردية',
            onTap: _onShiftReport,
          ),
        if (staffAllowed('print')) const SizedBox(width: 6),
        if (staffAllowed('dayclose') || staffAllowed('dayreopen'))
          btn(
            key: const Key('desk-daily-lock'),
            icon: _isTodayClosed()
                ? Icons.lock_rounded
                : Icons.lock_open_rounded,
            tip: _isTodayClosed() ? 'اليوم مُقفل' : 'قفل اليوم',
            color: _isTodayClosed() ? BrandColors.goldDark : null,
            onTap: _onLockTap,
          ),
      ],
    );
  }

  // ── قائمة سياق الصف — توأم قائمة م99 مع «وسم اللون» ──

  /// [getAnalOf] — دالة التحاليل المُمرَّرة من build() لتجنّب إعادة بناء الفهرس.
  List<CtxItem> _rowMenu(
    LedgerRow row,
    String? currentTag,
    List<AnalysisLink> Function(LedgerRow) getAnalOf,
  ) {
    return [
      if (!row.isExpense) ...[
        if (staffAllowed('patients.view'))
          CtxItem(
            'فتح ملف المريض',
            icon: Icons.person_rounded,
            keyId: 'open-profile',
            onTap: () => _openProfile(row),
          ),
        if (staffAllowed('records.add'))
          CtxItem(
            'زيارة سريعة جديدة',
            icon: Icons.add_circle_rounded,
            onTap: () => showQuickVisitSheet(
              context,
              name: row.name,
              clinic: row.clinic == kNoClinic ? '' : row.clinic,
              phone: row.phone,
              onFullOptions: () => openAddRecordSheet(context),
            ),
          ),
        if (staffAllowed('records.edit'))
          CtxItem(
            'تعديل السجل',
            icon: Icons.edit_rounded,
            onTap: () => _editRow(row),
          ),
        // معلومات مختصرة — ملاحظة هذه الدفعة/الزيارة حصراً (عمود
        // «ملاحظات مختصرة» يعرضها، وهذا مدخل تحريرها).
        if (row.id.isNotEmpty)
          CtxItem(
            'معلومات مختصرة',
            icon: Icons.sticky_note_2_outlined,
            keyId: 'quick-info',
            onTap: () => showQuickInfoDialog(
              context,
              ref,
              kind: row.kind,
              id: row.id,
              patientName: row.name,
            ),
          ),
      ],
      CtxItem(
        'نسخ الاسم',
        icon: Icons.copy_rounded,
        onTap: () {
          Clipboard.setData(ClipboardData(text: row.name));
          _snack('نُسخ الاسم');
        },
      ),
      CtxItem.divider,
      CtxTagRow(
        current: currentTag,
        onPick: (tag) => setRowTag(ref, _rowKey(row), tag),
      ),
      CtxItem.divider,
      // م147 — بند «إضافة التحاليل»: يظهر للصفوف غير المصروفية التي لا
      // تحاليل لها (وللموظفين ذوي صلاحية records.add)، يفتح نافذة كاش/تحويل
      // ويكتب صفاً معزولاً بسعر الإعدادات (سلوك «زيارة جديدة» حرفياً).
      // م168 — التفاعل بالتفعيل وحده: الإيقاف يخفي البند فوراً وكلياً.
      if (triAnalysesEnabled(ref.read(appConfigProvider)) &&
          !row.isExpense &&
          row.id.isNotEmpty &&
          getAnalOf(row).isEmpty &&
          staffAllowed('records.add'))
        CtxItem(
          'إضافة التحاليل',
          icon: Icons.science_outlined,
          keyId: 'add-analysis',
          onTap: () => _addRowAnalysis(row),
        ),
      // بند «حذف التحاليل» — يظهر فقط للصفوف غير المصروفية التي لها تحاليل
      // وللموظفين ذوي صلاحية records.delete. دخلٌ مخبري معزول لا يمس الزيارة.
      // م168 — التفاعل بالتفعيل وحده: الإيقاف يخفي البند فوراً وكلياً.
      if (triAnalysesEnabled(ref.read(appConfigProvider)) &&
          !row.isExpense &&
          getAnalOf(row).isNotEmpty &&
          staffAllowed('records.delete'))
        CtxItem(
          'حذف التحاليل',
          icon: Icons.delete_outline,
          destructive: true,
          // keyId: 'del-analysis' → Key('ctx-del-analysis') كما تطلب المواصفة.
          keyId: 'del-analysis',
          onTap: () => _deleteRowAnalyses(row, getAnalOf),
        ),
      if (staffAllowed(row.isExpense ? 'expenses.delete' : 'records.delete'))
        CtxItem(
          row.isExpense ? 'حذف المصروف' : 'حذف السجل',
          icon: Icons.delete_rounded,
          destructive: true,
          keyId: 'delete-row',
          onTap: () => _deleteRow(row),
        ),
    ];
  }

  /// فتح ملف المريض داخل لوحة مكتبية (لا صفحة فوق الشاشة كلها) —
  /// الدفعات الداخلية للملف محصورة في Navigator اللوحة.
  void _openProfile(LedgerRow row) {
    if (row.isExpense) return;
    showDesktopPanel<void>(
      context,
      title: row.name,
      subtitle: row.clinic == kNoClinic ? null : row.clinic,
      builder: (_) => DetailHost(
        hostKey: 'home-profile-${row.name}-${row.clinic}',
        child: PatientProfileScreen(
          patientName: row.name,
          clinic: row.clinic == kNoClinic ? '' : row.clinic,
        ),
      ),
    );
  }

  /// م100 — توأم _editRow حرفياً: ورقة الإدخال معبأة والحفظ يستبدل الأصل.
  Future<void> _editRow(LedgerRow row) async {
    if (row.id.isEmpty) {
      _snack('تعذّر تحديد الصف');
      return;
    }
    final repos = ref.read(reposProvider);
    if (row.kind == 'dp') {
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

  /// م117/م119 — توأم _deleteRow حرفياً (بوابات، توقيع الإدارة للمصروف،
  /// حوار الحذف المزدوج، الحذف المتسلسل، التدقيق، النبضات).
  Future<void> _deleteRow(LedgerRow row) async {
    if (row.id.isEmpty) {
      _snack('تعذّر تحديد الصف');
      return;
    }
    final repos = ref.read(reposProvider);
    if (!gateStaff(
      context,
      row.isExpense ? 'expenses.delete' : 'records.delete',
    )) {
      return;
    }
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

  /// حذف تحاليل صفٍّ مباشرةً من جدول سطح المكتب — دخلٌ مخبري معزول لا يمس
  /// مجاميع الزيارة. يحاكي نمط _deleteRow شكلاً وسلوكاً (حوار تأكيد + أزرار).
  /// م147 — إضافة تحليلٍ ثلاثيٍّ لزيارةٍ قائمة من قائمة سياق الصف: نجلب
  /// السجل الأصلي لنسخ تاريخه/يوم احتسابه/معرّف مريضه، ثم النافذة المشتركة.
  Future<void> _addRowAnalysis(LedgerRow row) async {
    final repos = ref.read(reposProvider);
    Map<String, Object?>? rec;
    for (final r in repos.records.getAll()) {
      if ('${r['id']}' == row.id) {
        rec = Map<String, Object?>.from(r);
        break;
      }
    }
    final added = await promptAddAnalysisToVisit(
      context,
      ref,
      analysisOf: row.id,
      patientName: row.name,
      patientId: rec?['patient_id'] as String?,
      clinic: row.clinic == kNoClinic ? '' : row.clinic,
      date: '${rec?['date'] ?? getCurrentDate()}',
      incomeDate: rec?['incomeDate'] as String?,
    );
    if (added && mounted) setState(() {});
  }

  /// [getAnalOf] — مُمرَّرة من _rowMenu لتجنّب إعادة بناء الفهرس.
  Future<void> _deleteRowAnalyses(
    LedgerRow row,
    List<AnalysisLink> Function(LedgerRow) getAnalOf,
  ) async {
    final links = getAnalOf(row);
    if (links.isEmpty) return;
    // حساب إجمالي قيمة التحاليل لعرضه في الحوار.
    final totalAmt = links.fold<num>(0, (s, a) => s + a.amount);
    final countStr = links.length.toString();
    final amtStr = formatNumber(totalAmt);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('حذف التحاليل'),
        content: Text(
          'حذف تحاليل هذا الصف ($countStr بقيمة $amtStr)؟'
          '\nدخل مخبري معزول — لا يمس مجاميع الزيارة.',
        ),
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
    final repos = ref.read(reposProvider);
    // حذف كل رابط له معرّف غير فارغ عبر الحذف الناعم المتزامن.
    for (final a in links) {
      if (a.id.isNotEmpty) repos.records.delete(a.id);
    }
    setState(() {});
    _snack('تم حذف التحاليل');
  }

  // ═══ م120 — تقرير تسليم الوردية (توأم حرفي لتدفق الهاتف) ═══

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
                  key: const Key('desk-shift-staff'),
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
                key: const Key('desk-shift-report-go'),
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

  Future<void> _printShiftReport(String username, String display) async {
    final repos = ref.read(reposProvider);
    final today = getCurrentDate();
    final all = todayLedgerRows(
      repos.records.getAll().cast<Map<String, Object?>>(),
      repos.prosthetics.getAll().cast<Map<String, Object?>>(),
      repos.debts.getAll().cast<Map<String, Object?>>(),
    ).reversed.toList();
    final rowsAll = [...all, ..._todayExpenseRows(null).reversed];
    final rows = username.isEmpty
        ? rowsAll
        : [
            for (final r in rowsAll)
              if (r.by == username) r,
          ];
    final orphan = username.isEmpty
        ? 0
        : rowsAll.where((r) => r.by.isEmpty).length;
    // م151 — قيم التحاليل تدخل إجماليات التقرير مرةً واحدة (من صفوفها
    // المستقلة، منسوبةً للموظف عند تقرير موظفٍ بعينه — قرار المالك).
    final tot = totalsWithAnalyses(
      ledgerTotals(rows),
      dayAnalysesTotals(
        repos.records.getAll().cast<Map<String, Object?>>(),
        by: username,
      ),
    );
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

  // ═══ م104 — قفل اليوم (توأم حرفي لتدفق الهاتف) ═══

  Future<void> _onLockTap() async {
    final today = getCurrentDate();
    final store = DayCloseStore(ref.read(reposProvider).settings);
    if (store.isClosed(today)) {
      if (!gateStaff(context, 'dayreopen')) return;
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
              key: const Key('desk-day-reopen'),
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
            key: const Key('desk-day-close-confirm'),
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

  Future<void> _closeDayAndPrint(String today) async {
    final repos = ref.read(reposProvider);
    final all = todayLedgerRows(
      repos.records.getAll().cast<Map<String, Object?>>(),
      repos.prosthetics.getAll().cast<Map<String, Object?>>(),
      repos.debts.getAll().cast<Map<String, Object?>>(),
    ).reversed.toList();
    final rows = [...all, ..._todayExpenseRows(null).reversed];
    // م151 — قيم التحاليل تدخل إجماليات التقفيل ولقطته مرةً واحدة
    // (من صفوفها المستقلة حصراً — قرار المالك).
    final tot = totalsWithAnalyses(
      ledgerTotals(rows),
      dayAnalysesTotals(
        repos.records.getAll().cast<Map<String, Object?>>(),
      ),
    );
    final n = formatNumber;
    final cfg = ref.read(appConfigProvider);
    final cur = '${cfg['currency'] ?? 'د.ل'}';

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
}

// ── رقاقة طريقة الدفع ───────────────────────────────────────────────────────

class _PayChip extends StatelessWidget {
  const _PayChip({required this.row});
  final LedgerRow row;

  @override
  Widget build(BuildContext context) {
    // م115 — دفعة الدين تعرض طريقتها الحقيقية مع وسمها.
    final label = row.kind == 'dp'
        ? (row.effectiveMethod.isEmpty ? row.payment : row.effectiveMethod)
        : row.payment;
    final tagged = row.kind == 'dp'
        ? (row.remaining <= 0 ? 'نهائية' : 'دفعة دين')
        : null;
    final (bg, fg) = switch (label) {
      'كاش' => (const Color(0x1A1E7A52), BrandColors.green),
      'تحويل' => (const Color(0x1A2563EB), const Color(0xFF2563EB)),
      // (قرار المالك) «دين» بأصفر غامق من هوية التطبيق (لا أحمر) —
      // ويبقى «مصروف» أحمر تمييزاً، و«دفعة دين» ذهبيّاً كما هو.
      'دين' => (const Color(0x22B8860B), const Color(0xFF8A6D1B)),
      'مصروف' => (const Color(0x1AC0392B), BrandColors.red),
      _ => (const Color(0x14C9A24B), BrandColors.goldDark),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        tagged == null ? label : '$label ($tagged)',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: fg,
        ),
      ),
    );
  }
}

// ── فلتر متعدد الاختيار (عيادة/دفع) ─────────────────────────────────────────

class _MultiFilter extends StatelessWidget {
  const _MultiFilter({
    required this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final List<String> options;
  final Set<String> selected;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      builder: (ctx, ctl, _) => FilterChip(
        avatar: Icon(
          Icons.arrow_drop_down_rounded,
          size: 16,
          color: selected.isEmpty ? BrandColors.mut : Colors.white,
        ),
        label: Text(
          selected.isEmpty ? label : '$label (${selected.length})',
          style: const TextStyle(fontSize: 11),
        ),
        selected: selected.isNotEmpty,
        selectedColor: BrandColors.brand600,
        labelStyle: TextStyle(
          color: selected.isEmpty ? BrandColors.ink : Colors.white,
          fontWeight: FontWeight.w700,
        ),
        visualDensity: VisualDensity.compact,
        onSelected: (_) => ctl.isOpen ? ctl.close() : ctl.open(),
      ),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(BrandColors.surface),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      menuChildren: [
        SizedBox(
          width: 220,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final o in options)
                StatefulBuilder(
                  builder: (ctx, setLocal) => CheckboxListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: selected.contains(o),
                    title: Text(o, style: const TextStyle(fontSize: 12)),
                    onChanged: (v) {
                      setLocal(() {
                        v == true ? selected.add(o) : selected.remove(o);
                      });
                      onChanged();
                    },
                  ),
                ),
              if (selected.isNotEmpty)
                TextButton(
                  onPressed: () {
                    selected.clear();
                    onChanged();
                  },
                  child: const Text('مسح', style: TextStyle(fontSize: 11.5)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── لوحة الودجات — بطاقات متجاورة قابلة لإعادة الترتيب بالسحب ───────────────

/// م-تصميم 2026 (قرار المالك) — ملخص الرئيسية مصفوفةٌ محاذاة بلا أي
/// تمرير أفقي: ثلاثة أعمدة ثابتة (كاش | تحويل | الإجمالي) والأرقام تحت
/// بعضها تماماً، فحسابُ أي عمودٍ قراءةٌ رأسية واحدة:
///
///   الصف ١ (دائم):        كاش        تحويل        إجمالي الإيراد
///   الصف ٢ (مع المصروفات): مصروف كاش  مصروف تحويل  إجمالي المصروفات
///   الصف ٣ (مع المصروفات): صافي الكاش صافي التحويل الصافي النهائي★
///
/// الصفان ٢ و٣ يظهران فقط عند تفعيل زر «المصروفات» فوق الجدول (سلوك
/// الهاتف نفسه)، والصافي النهائي مبرزٌ بهوية ذهبية. استُبدل بهذا شريطُ
/// البطاقات الأفقي المتمرر القابل لإعادة الترتيب — إعادة الترتيب أُحيلت
/// (تتعارض مع المحاذاة الصارمة المطلوبة)؛ كل القيم والحسابات باقية،
/// والدين المتبقي انتقل لبطاقة اليوم فصار ظاهراً دائماً.
class _DeskDashboard extends ConsumerWidget {
  const _DeskDashboard({
    required this.tot,
    required this.cur,
    required this.date,
    required this.closed,
    required this.showExpenses,
  });

  final LedgerTotals tot;
  final String cur;
  final String date;
  final bool closed;
  final bool showExpenses;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = formatNumber;
    const cashColor = Color(0xFF15604A);
    const xferColor = Color(0xFF2563EB);
    const totColor = Color(0xFF1E7A52);
    const expColor = Color(0xFFB8860B);

    Widget cellRow(List<Widget> cells) => Expanded(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < cells.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: cells[i]),
          ],
        ],
      ),
    );

    // ارتفاع مضبوط (لا IntrinsicHeight) يتحرّك بسلاسة بين وضعَي الطي/العرض
    // — بلا أي تمرير أفقي على أي دقة شاشة. صفٌّ واحد مطويّاً، ثلاثة موسّعاً.
    // بأرضية 78 كي لا تفيض بطاقة اليوم (عنوان + عدد الحالات + الدين) حين الطي.
    const rowH = 58.0;
    final matrixH = showExpenses ? (rowH * 3 + 16) : rowH;
    final totalH = matrixH < 88 ? 88.0 : matrixH;

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        height: totalH,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _HeroCard(
              date: date,
              count: tot.count,
              closed: closed,
              debt: '${n(tot.remaining)} $cur',
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                children: [
                  // الصف ١ — الإيراد (دائم الظهور).
                  cellRow([
                    _MatrixCell(
                      key: const ValueKey('dash-cash'),
                      icon: Icons.money_rounded,
                      label: 'كاش',
                      value: n(tot.paidBy['كاش'] ?? 0),
                      cur: cur,
                      color: cashColor,
                    ),
                    _MatrixCell(
                      key: const ValueKey('dash-transfer'),
                      icon: Icons.swap_horiz_rounded,
                      label: 'تحويل',
                      value: n(tot.paidBy['تحويل'] ?? 0),
                      cur: cur,
                      color: xferColor,
                    ),
                    _MatrixCell(
                      key: const ValueKey('dash-paid'),
                      icon: Icons.payments_rounded,
                      label: 'إجمالي الإيراد',
                      value: n(tot.paid),
                      cur: cur,
                      color: totColor,
                    ),
                  ]),
                  // الصفان ٢ و٣ — المصروفات والصوافي (مع زر المصروفات).
                  if (showExpenses) ...[
                    const SizedBox(height: 8),
                    cellRow([
                      _MatrixCell(
                        key: const ValueKey('dash-exp-cash'),
                        icon: Icons.money_off_rounded,
                        label: 'مصروف كاش',
                        value: n(tot.expenseBy['كاش'] ?? 0),
                        cur: cur,
                        color: expColor,
                        negative: true,
                      ),
                      _MatrixCell(
                        key: const ValueKey('dash-exp-transfer'),
                        icon: Icons.mobile_off_rounded,
                        label: 'مصروف تحويل',
                        value: n(tot.expenseBy['تحويل'] ?? 0),
                        cur: cur,
                        color: expColor,
                        negative: true,
                      ),
                      _MatrixCell(
                        key: const ValueKey('dash-exp-total'),
                        icon: Icons.receipt_long_rounded,
                        label: 'إجمالي المصروفات',
                        value: n(tot.expense),
                        cur: cur,
                        color: expColor,
                        negative: true,
                      ),
                    ]),
                    const SizedBox(height: 8),
                    cellRow([
                      _MatrixCell(
                        key: const ValueKey('dash-net-cash'),
                        icon: Icons.savings_rounded,
                        label: 'صافي الكاش',
                        value: n(tot.netOf('كاش')),
                        cur: cur,
                        color: cashColor,
                      ),
                      _MatrixCell(
                        key: const ValueKey('dash-net-transfer'),
                        icon: Icons.savings_rounded,
                        label: 'صافي التحويل',
                        value: n(tot.netOf('تحويل')),
                        cur: cur,
                        color: xferColor,
                      ),
                      _MatrixCell(
                        key: const ValueKey('dash-net-final'),
                        icon: Icons.account_balance_wallet_rounded,
                        label: 'الصافي النهائي',
                        value: n(tot.net),
                        cur: cur,
                        color: BrandColors.goldDark,
                        emphasized: true,
                      ),
                    ]),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// خلية مصفوفة الملخص: تسميةٌ صغيرة وقيمةٌ كبيرة بأرقامٍ جدولية —
/// الأعمدة متساوية العرض (Expanded) فالأرقام تتحاذى رأسياً تماماً.
/// [emphasized] للصافي النهائي: خلفية ذهبية مبرزة وخط أكبر.
class _MatrixCell extends StatelessWidget {
  const _MatrixCell({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.cur,
    required this.color,
    this.negative = false,
    this.emphasized = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final String cur;
  final Color color;

  /// قيمة خصم (مصروف) — تُسبق بإشارة −.
  final bool negative;

  /// إبراز بصري (الصافي النهائي).
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: emphasized
            ? const Color.fromRGBO(201, 162, 75, .16)
            : BrandColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: emphasized ? BrandColors.gold : BrandColors.line,
          width: emphasized ? 1.4 : 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: emphasized ? 20 : 16,
            color: emphasized ? BrandColors.goldDark : color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: emphasized ? BrandColors.goldDark : BrandColors.mut,
                  ),
                ),
                const SizedBox(height: 1),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        if (negative)
                          TextSpan(
                            text: '− ',
                            style: TextStyle(
                              fontSize: emphasized ? 18 : 15,
                              fontWeight: FontWeight.w900,
                              color: BrandColors.red,
                            ),
                          ),
                        TextSpan(
                          text: value,
                          style: TextStyle(
                            fontSize: emphasized ? 18 : 15,
                            fontWeight: FontWeight.w900,
                            color: emphasized ? BrandColors.goldDark : color,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        TextSpan(
                          text: '  $cur',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: BrandColors.mut2,
                          ),
                        ),
                      ],
                    ),
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.date,
    required this.count,
    required this.closed,
    required this.debt,
  });

  final String date;
  final int count;
  final bool closed;

  /// الدين المتبقي اليوم — انتقل من بطاقة مستقلة إلى هنا فصار ظاهراً
  /// دائماً (كان يختفي عند عرض المصروفات في الترتيب القديم).
  final String debt;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: BrandColors.brandGradient,
        borderRadius: BorderRadius.circular(14),
      ),
      // م146/ملحق — كانت الأسطر الثلاثة بارتفاعاتٍ صلبة تفيض بكسلاتٍ قليلة
      // مع مقاييس خطوطٍ مختلفة (كشفتها لقطات م146). FittedBox ينكمش
      // بالكاد عند الضيق فقط ويبقى محايداً في الوضع الطبيعي.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerStart,
        child: SizedBox(
          width: 222,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.today_rounded,
                    color: BrandColors.goldLight,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
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
                ],
              ),
              const SizedBox(height: 5),
              Row(
                children: [
                  Text(
                    '$count حالة',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (closed)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
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
                            size: 11,
                            color: BrandColors.goldLight,
                          ),
                          SizedBox(width: 3),
                          Text(
                            'مُقفل',
                            style: TextStyle(
                              color: BrandColors.goldLight,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                key: const ValueKey('dash-debt'),
                children: [
                  const Icon(
                    Icons.hourglass_bottom_rounded,
                    size: 12,
                    color: Color(0xFFF0B9B0),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        'الدين المتبقي: $debt',
                        maxLines: 1,
                        style: const TextStyle(
                          color: Color(0xFFF6D9D4),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
