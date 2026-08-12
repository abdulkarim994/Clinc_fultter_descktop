/// م154 — خزينة الهاتف الجديدة (قرار المالك): بروح تصميم الديون الذي
/// اختاره — صفوفٌ أنيقة بسيطة وجداول مضغوطة منظمة.
///
/// وضعان يبدّل بينهما زرٌّ صغير أعلى الشاشة (توأم مبدّل الحجوزات):
/// • «التفصيل»: صفٌّ بسيط لكل عيادة (اسمها + إجماليها الشهري) وصفّان
///   مستقلان: «إيراد التحاليل الثلاثية» و«المصروفات». الضغط يفتح شاشةً
///   بجدولٍ مضغوط (التاريخ/الاسم/الدفع/القيمة) فوقه بحثٌ وفلترة كاش/
///   تحويل وطباعةٌ حسب الظاهر — وتفصيل العيادة فيه تبويب «تركيبات»
///   بجدولٍ منظم بنفس معلومات البطاقات السابقة.
/// • «الإجمالي»: جدولٌ واحد — العيادات/التحاليل/المصروفات × (كاش/تحويل/
///   إجمالي) + صف الصافي بعد الخصم.
///
/// كل القيم بنطاق شهر المبدّل القائم فتصفر تلقائياً مطلع كل شهر —
/// والتحاليل ضمنها الآن (أرشيفها الدائم في «السجلات»). المنطق المالي
/// كله من treasury_logic النقية بلا أي تعديل.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/js_compat.dart';
import '../expenses/expenses_report.dart' show expenseCategoryLabel;
import '../print/treatment_tables.dart' show formatNumber;
import '../staff/staff_gate.dart' show staffAllowed;
import 'analyses_filter.dart' show monthAnalysesRows, monthAnalysesTotals;
// م168 — رؤية الشهر المركزية للتحاليل (اختفاء شامل بعد تاريخ الإيقاف).
import '../settings/analyses3.dart' show triVisibleInMonth;
// م170 — العيادات المؤرشفة (عرض تاريخي) واللقطات المجمدة للمحذوفة.
import '../settings/clinic_admin.dart'
    show FrozenRow, archivedClinicsOf, frozenRowsForMonth, frozenTotalsForMonth;
import 'finance_screen.dart' show financeRevProvider;
import 'treasury_logic.dart';
import 'treasury_tables.dart';

typedef _JMap = Map<String, Object?>;

class TreasurySection extends ConsumerStatefulWidget {
  const TreasurySection({super.key});

  @override
  ConsumerState<TreasurySection> createState() => _TreasurySectionState();
}

class _TreasurySectionState extends ConsumerState<TreasurySection> {
  /// وضع «الإجمالي» — الافتراضي «التفصيل».
  bool _totalsView = false;

  TreasurySlice _slice() {
    ref.watch(financeRevProvider);
    final repos = ref.watch(reposProvider);
    return TreasurySlice(
      ref.watch(selectedMonthProvider),
      records: repos.records.getAll(),
      prosthetics: repos.prosthetics.getAll(),
      debts: repos.debts.getAll(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _slice();
    final repos = ref.watch(reposProvider);
    final records = repos.records.getAll().cast<Map<String, Object?>>();
    final cur = ref.watch(currencyProvider);
    final clinics = ref.watch(clinicsProvider);
    final n = formatNumber;
    final det = staffAllowed('treasury.details');
    final anal = monthAnalysesTotals(records, month: s.month);
    final ex = repos.expenses.monthExpenseTotals(s.month);
    final t = treasuryTotals(s);
    // م168 — رؤية التحاليل لهذا الشهر: الأشهر التاريخية (حتى شهر
    // الإيقاف) تبقى ببطاقتها وقيمها، والتالية تختفي كلياً بلا فراغ.
    final cfg170 = ref.watch(appConfigProvider);
    final triSee = triVisibleInMonth(cfg170, s.month);
    // م170 — العيادات المؤرشفة ذات نشاطٍ بالشهر (صفوفها التاريخية باقية)
    // + صفوف العيادات المحذوفة من لقطاتها المجمدة (عرضٌ فقط).
    final archivedActive = [
      for (final a in archivedClinicsOf(cfg170))
        if (clinicCash(s, a) + clinicXfer(s, a) + clinicProsTotalPaid(s, a) !=
            0)
          a,
    ];
    final frozenRows = frozenRowsForMonth(cfg170, s.month);
    final frozenTot = frozenTotalsForMonth(cfg170, s.month);

    return ListView(
      key: const Key('treasury-main'),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 90),
      children: [
        // ── الرأس: العنوان + مبدّل التفصيل/الإجمالي ─────────────────────
        Row(children: [
          Icon(Icons.account_balance_rounded,
              size: 17, color: BrandColors.goldDark),
          const SizedBox(width: 7),
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('خزينة ${s.month}',
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                        color: BrandColors.brandText)),
              ),
            ),
          ),
          TreasuryViewSwitcher(
            totals: _totalsView,
            onChanged: (v) => setState(() => _totalsView = v),
          ),
        ]),
        const SizedBox(height: 12),

        if (_totalsView)
          // ── وضع «الإجمالي»: الجدول الواحد ────────────────────────────
          TreasuryTotalsTable(
            month: s.month,
            // م170 — مجاميع الشهر تشمل لقطات العيادات المحذوفة المجمدة
            // (السجل المالي التاريخي يبقى بأرقامه حرفياً — قرار المالك).
            clinicsCash: t.cash + frozenTot.cash,
            clinicsXfer: t.xfer + frozenTot.xfer,
            // م156 — التركيبات المدفوعة موزعة كاش/تحويل بصفٍّ مستقل.
            prosCash: prosPaidByMethod(s.pros, s.pdPays).cash + frozenTot.prosCash,
            prosXfer: prosPaidByMethod(s.pros, s.pdPays).xfer + frozenTot.prosXfer,
            analCash: anal.cash + frozenTot.analCash,
            analXfer: anal.transfer + frozenTot.analXfer,
            expCash: ex.cash,
            expXfer: ex.xfer,
            expTotal: ex.total,
            det: det,
            dense: true,
            // م168 — إخفاء صف التحاليل للأشهر التالية للإيقاف.
            showAnal: triSee,
          )
        else ...[
          // ── وضع «التفصيل»: صفوف بسيطة بروح الديون ────────────────────
          for (final cli in clinics) ...[
            TreasuryMasterRow(
              key: Key('tr2-row-$cli'),
              icon: Icons.apartment_rounded,
              label: cli,
              value: det
                  ? '${n(clinicCash(s, cli) + clinicXfer(s, cli) + clinicProsTotalPaid(s, cli))} $cur'
                  : '—',
              onTap: () => _openDetail(context, s, 'c:$cli'),
            ),
            const SizedBox(height: 8),
          ],
          // م170 — العيادات المؤرشفة (اسمٌ قديم بعد تعديلٍ «للجديد فقط»):
          // صفوفها التاريخية باقية فتعرض كأي عيادة — عرضٌ تاريخي.
          for (final cli in archivedActive) ...[
            TreasuryMasterRow(
              key: Key('tr2-row-$cli'),
              icon: Icons.history_rounded,
              label: '$cli (مؤرشفة)',
              value: det
                  ? '${n(clinicCash(s, cli) + clinicXfer(s, cli) + clinicProsTotalPaid(s, cli))} $cur'
                  : '—',
              onTap: () => _openDetail(context, s, 'c:$cli'),
            ),
            const SizedBox(height: 8),
          ],
          // م170 — العيادات المحذوفة: قيم اللقطة المجمدة (عرضٌ فقط —
          // البيانات نفسها حُذفت فعلياً، والمال التاريخي محفوظ).
          for (final f in frozenRows) ...[
            TreasuryMasterRow(
              key: Key('tr2-row-frozen-${f.clinic}'),
              icon: Icons.lock_outline_rounded,
              label: '${f.clinic} 🔒 (محذوفة)',
              value: det
                  ? '${n(jsNumOr0(f.fields['cash']) + jsNumOr0(f.fields['xfer']) + jsNumOr0(f.fields['prosCash']) + jsNumOr0(f.fields['prosXfer']))} $cur'
                  : '—',
              onTap: () => _showFrozenDetail(context, f, cur),
            ),
            const SizedBox(height: 8),
          ],
          Divider(height: 18, color: BrandColors.line),
          // م168 — بطاقة التحاليل وفاصلها السفلي يختفيان معاً بعد الإيقاف.
          if (triSee) ...[
            TreasuryMasterRow(
              key: const Key('tr2-row-anal'),
              icon: Icons.biotech_rounded,
              label: 'إيراد التحاليل الثلاثية',
              value: det ? '${n(anal.cash + anal.transfer)} $cur' : '—',
              color: BrandColors.green,
              onTap: () => _openDetail(context, s, 'anal'),
            ),
            const SizedBox(height: 8),
          ],
          TreasuryMasterRow(
            key: const Key('tr2-row-exp'),
            icon: Icons.receipt_long_rounded,
            label: 'المصروفات',
            value: det ? '${n(ex.total)} $cur' : '—',
            color: BrandColors.red,
            onTap: () => _openDetail(context, s, 'exp'),
          ),
        ],
      ],
    );
  }

  /// م170 — تفاصيل لقطةٍ مجمدة لعيادةٍ محذوفة: أرقام الشهر للعرض فقط.
  void _showFrozenDetail(BuildContext context, FrozenRow f, String cur) {
    final n = formatNumber;
    num v(String k) => jsNumOr0(f.fields[k]);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${f.clinic} — سجل مالي مجمد',
            style: const TextStyle(fontSize: 14)),
        content: Text(
          'عيادة محذوفة — بياناتها زالت نهائياً وسجلها المالي محفوظ:\n\n'
          '• إيراد كاش: ${n(v('cash'))} $cur\n'
          '• إيراد تحويل: ${n(v('xfer'))} $cur\n'
          '• تركيبات (كاش/تحويل): ${n(v('prosCash'))} / ${n(v('prosXfer'))} $cur\n'
          '• تحاليل ثلاثية (كاش/تحويل): ${n(v('analCash'))} / ${n(v('analXfer'))} $cur\n'
          '• أرباح: الإيراد ${n(v('revenue'))} — الطبيب ${n(v('doctor'))} — '
          'العيادة ${n(v('clinicShare'))} $cur',
          style: const TextStyle(fontSize: 12.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إغلاق')),
        ],
      ),
    );
  }

  void _openDetail(BuildContext context, TreasurySlice s, String sel) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _TreasuryDetailScreen(sel: sel, month: s.month),
      ),
    );
  }
}

/// شاشة تفصيل بندٍ (عيادة/تحاليل/مصروفات) — جدول مضغوط بفلاتره وطباعته،
/// وتفصيل العيادة فيه تبويب «تركيبات».
class _TreasuryDetailScreen extends ConsumerStatefulWidget {
  const _TreasuryDetailScreen({required this.sel, required this.month});

  final String sel;
  final String month;

  @override
  ConsumerState<_TreasuryDetailScreen> createState() =>
      _TreasuryDetailScreenState();
}

class _TreasuryDetailScreenState
    extends ConsumerState<_TreasuryDetailScreen> {
  bool _prosTab = false;

  /// م173 — مقبض رجوع جدول التركيبات (يغلق تفاصيل الحالة المفتوحة).
  final _prosBack = ProsTableBackHandle();

  @override
  Widget build(BuildContext context) {
    ref.watch(financeRevProvider);
    final repos = ref.watch(reposProvider);
    final s = TreasurySlice(
      widget.month,
      records: repos.records.getAll(),
      prosthetics: repos.prosthetics.getAll(),
      debts: repos.debts.getAll(),
    );
    final records = repos.records.getAll().cast<Map<String, Object?>>();
    final isClinic = widget.sel.startsWith('c:');
    final clinic = isClinic ? widget.sel.substring(2) : '';
    final title = isClinic
        ? clinic
        : widget.sel == 'anal'
            ? 'إيراد التحاليل الثلاثية'
            : 'المصروفات';

    final rows = isClinic
        ? clinicMonthMoves(s, clinic)
        : widget.sel == 'anal'
            ? monthAnalysesRows(records, month: widget.month)
            : <_JMap>[
                for (final e in repos.expenses.getByMonth(widget.month))
                  {
                    'date': e['date'],
                    'name': ('${e['title'] ?? ''}'.trim().isNotEmpty)
                        ? e['title']
                        : expenseCategoryLabel(e['category']),
                    '_pay': ('${e['payment'] ?? ''}'.trim() == 'تحويل')
                        ? 'تحويل'
                        : 'كاش',
                    'amount': e['amount'],
                  },
              ];

    final doctorPct =
        jsNumOr0(jsOr(ref.watch(appConfigProvider)['doctorPct'], 50));

    // م173 — زر رجوع النظام تسلسلاً (قرار المالك): تفاصيل حالة تركيبٍ
    // مفتوحة تُغلق أولاً، ثم تبويب «التركيبات» يعود إلى «الحركات»، ثم
    // رجوعٌ آخر يغادر لشاشة الخزينة.
    return PopScope(
      canPop: !_prosTab,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_prosBack.handleBack()) return; // أُغلقت تفاصيل الحالة.
        setState(() => _prosTab = false); // التركيبات ⇒ الحركات.
      },
      child: Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text('$title — ${widget.month}',
            style:
                const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
        actions: [
          if (isClinic)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: Center(
                child: SegmentedButton<bool>(
                  key: const Key('tr2-clinic-tab'),
                  showSelectedIcon: false,
                  style: SegmentedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: BrandColors.surface2,
                    foregroundColor: BrandColors.mut,
                    selectedBackgroundColor: BrandColors.goldDark,
                    selectedForegroundColor: Colors.white,
                    side: BorderSide(
                        color: BrandColors.gold.withValues(alpha: .4)),
                  ),
                  segments: const [
                    ButtonSegment(
                        value: false,
                        label: Text('الحركات',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700))),
                    ButtonSegment(
                        value: true,
                        label: Text('التركيبات',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700))),
                  ],
                  selected: {_prosTab},
                  onSelectionChanged: (v) =>
                      setState(() => _prosTab = v.first),
                ),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
        children: [
          if (isClinic && _prosTab)
            TreasuryProsTable(
              groups: prosGrouped(s, clinic, doctorPct),
              // م157 — صفوف الجدول الجديد: حالات الشهر + دفعات ديون
              // الشهور السابقة صفوفاً مستقلة موسومة.
              cases: prosCaseRows(
                s,
                clinic,
                allDebts:
                    repos.debts.getAll().cast<Map<String, Object?>>(),
                allPros: repos.prosthetics
                    .getAll()
                    .cast<Map<String, Object?>>(),
                doctorPct: doctorPct,
              ),
              doctorPct: doctorPct,
              month: widget.month,
              clinic: clinic,
              dense: true,
              backHandle: _prosBack,
            )
          else
            TreasuryMovesTable(
              title: widget.sel == 'exp' ? 'مصروفات الشهر' : 'حركات $title',
              subtitle: widget.month,
              rows: rows,
              dense: true,
              showService: isClinic,
              originalPrint: isClinic,
              doctorPct: doctorPct,
            ),
        ],
      ),
      ),
    );
  }
}
