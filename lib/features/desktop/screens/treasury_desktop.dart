/// م154 — الخزينة المكتبية الجديدة (قرار المالك): جداول منظمة بنمط
/// جدول المختبرات الذي اختاره.
///
/// وضعان يبدّل بينهما زرٌّ صغير أعلى الشاشة (توأم مبدّل الحجوزات):
/// • «التفصيل»: يمينٌ بصفوفٍ بسيطة — كل عيادة باسمها وجنبه إجماليها
///   الشهري، وصفّان مستقلان: «إيراد التحاليل الثلاثية» و«المصروفات».
///   الضغط يفتح يساراً جدولاً منظماً (التاريخ/الاسم/الدفع/القيمة) فوقه
///   بحثٌ وفلترة كاش/تحويل وطباعةٌ حسب الظاهر؛ وتفصيل العيادة فيه تبويب
///   «تركيبات» بجدولٍ منظم بنفس معلومات البطاقات السابقة.
/// • «الإجمالي»: جدولٌ واحد — العيادات/التحاليل/المصروفات × (كاش/تحويل/
///   إجمالي) + صف الصافي بعد الخصم.
///
/// كل القيم بنطاق شهر المبدّل القائم فتصفر تلقائياً مطلع كل شهر —
/// والتحاليل ضمنها الآن (أرشيفها الدائم انتقل إلى «السجلات»). المنطق
/// المالي كله من treasury_logic النقية بلا أي تعديل.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/js_compat.dart';
import '../../expenses/expenses_report.dart' show expenseCategoryLabel;
import '../../finance/analyses_filter.dart'
    show monthAnalysesRows, monthAnalysesTotals;
import '../../finance/finance_screen.dart' show financeRevProvider;
import '../../finance/treasury_logic.dart';
import '../../finance/treasury_tables.dart';
import '../../print/treatment_tables.dart' show formatNumber;
import '../../staff/staff_gate.dart' show staffAllowed;
import '../desktop_prefs.dart' show desktopPrefsProvider, saveDesktopPref;
import '../widgets/split_view.dart' show DesktopSplitView;

typedef _JMap = Map<String, Object?>;

/// مفتاح حفظ وضع العرض (تفصيل/إجمالي) — محلي للجهاز.
const _kViewKey = 'treasury.view.totals';

class DesktopTreasuryScreen extends ConsumerStatefulWidget {
  const DesktopTreasuryScreen({super.key});

  @override
  ConsumerState<DesktopTreasuryScreen> createState() =>
      _DesktopTreasuryScreenState();
}

class _DesktopTreasuryScreenState
    extends ConsumerState<DesktopTreasuryScreen> {
  /// الاختيار في وضع التفصيل: null | 'anal' | 'exp' | عيادة بسابقة c:.
  String? _sel;

  /// تبويب تفصيل العيادة: false = الحركات، true = التركيبات.
  bool _prosTab = false;

  /// تجاوز محلي لوضع العرض — null = اتبع المحفوظ (الافتراضي: التفصيل).
  bool? _totalsView;

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

    final saved = ref.watch(desktopPrefsProvider)[_kViewKey];
    final totalsView = _totalsView ?? (saved is bool ? saved : false);

    // ── الرأس: العنوان + مبدّل التفصيل/الإجمالي ──────────────────────────
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Row(children: [
        Icon(Icons.account_balance_rounded,
            size: 18, color: BrandColors.goldDark),
        const SizedBox(width: 8),
        Expanded(
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text('خزينة ${s.month}',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: BrandColors.brandText)),
            ),
          ),
        ),
        TreasuryViewSwitcher(
          totals: totalsView,
          onChanged: (v) {
            setState(() => _totalsView = v);
            saveDesktopPref(ref, _kViewKey, v);
          },
        ),
      ]),
    );

    // ── وضع «الإجمالي»: جدول واحد بعرضٍ مريح ─────────────────────────────
    if (totalsView) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    TreasuryTotalsTable(
                      month: s.month,
                      clinicsCash: t.cash,
                      clinicsXfer: t.xfer,
                      // م156 — التركيبات المدفوعة كاش/تحويل بصفٍّ مستقل.
                      prosCash: prosPaidByMethod(s.pros, s.pdPays).cash,
                      prosXfer: prosPaidByMethod(s.pros, s.pdPays).xfer,
                      analCash: anal.cash,
                      analXfer: anal.transfer,
                      expCash: ex.cash,
                      expXfer: ex.xfer,
                      expTotal: ex.total,
                      det: det,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    // ── وضع «التفصيل»: Master/Detail بنمط جدول المختبرات ─────────────────
    final master = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
            children: [
              for (final cli in clinics) ...[
                TreasuryMasterRow(
                  key: Key('tr2-row-$cli'),
                  icon: Icons.apartment_rounded,
                  label: cli,
                  value: det
                      ? '${n(clinicCash(s, cli) + clinicXfer(s, cli) + clinicProsTotalPaid(s, cli))} $cur'
                      : '—',
                  selected: _sel == 'c:$cli',
                  onTap: () => setState(() {
                    _sel = 'c:$cli';
                    _prosTab = false;
                  }),
                ),
                const SizedBox(height: 8),
              ],
              Divider(height: 18, color: BrandColors.line),
              TreasuryMasterRow(
                key: const Key('tr2-row-anal'),
                icon: Icons.biotech_rounded,
                label: 'إيراد التحاليل الثلاثية',
                value: det ? '${n(anal.cash + anal.transfer)} $cur' : '—',
                color: BrandColors.green,
                selected: _sel == 'anal',
                onTap: () => setState(() => _sel = 'anal'),
              ),
              const SizedBox(height: 8),
              TreasuryMasterRow(
                key: const Key('tr2-row-exp'),
                icon: Icons.receipt_long_rounded,
                label: 'المصروفات',
                value: det ? '${n(ex.total)} $cur' : '—',
                color: BrandColors.red,
                selected: _sel == 'exp',
                onTap: () => setState(() => _sel = 'exp'),
              ),
            ],
          ),
        ),
      ],
    );

    return DesktopSplitView(
      id: 'treasury',
      emptyIcon: Icons.account_balance_rounded,
      emptyTitle: 'اختر بنداً لعرض جدوله',
      emptyHint: 'اضغط عيادةً أو التحاليل أو المصروفات من القائمة',
      masterWidth: 380,
      minMasterWidth: 320,
      maxMasterWidth: 520,
      master: master,
      detail: _sel == null
          ? null
          : KeyedSubtree(
              key: ValueKey('tr2-detail-$_sel-$_prosTab'),
              child: _detail(s, records, cur),
            ),
    );
  }

  // ── لوح التفصيل ───────────────────────────────────────────────────────

  Widget _detail(TreasurySlice s, List<_JMap> records, String cur) {
    final sel = _sel!;
    final isClinic = sel.startsWith('c:');
    final clinic = isClinic ? sel.substring(2) : '';
    final title = isClinic
        ? clinic
        : sel == 'anal'
            ? 'إيراد التحاليل الثلاثية'
            : 'المصروفات';

    final rows = isClinic
        ? clinicMonthMoves(s, clinic)
        : sel == 'anal'
            ? monthAnalysesRows(records, month: s.month)
            : <_JMap>[
                for (final e
                    in ref.watch(reposProvider).expenses.getByMonth(s.month))
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

    return ListView(
      key: const Key('tr2-detail-pane'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      children: [
        Row(children: [
          Icon(
              isClinic
                  ? Icons.apartment_rounded
                  : sel == 'anal'
                      ? Icons.biotech_rounded
                      : Icons.receipt_long_rounded,
              size: 18,
              color: sel == 'exp' ? BrandColors.red : BrandColors.goldDark),
          const SizedBox(width: 8),
          Expanded(
            child: Text(title,
                key: const Key('tr2-detail-title'),
                style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w900,
                    color: BrandColors.brandText)),
          ),
          // تبويبا تفصيل العيادة: الحركات | التركيبات.
          if (isClinic)
            SegmentedButton<bool>(
              key: const Key('tr2-clinic-tab'),
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                backgroundColor: BrandColors.surface2,
                foregroundColor: BrandColors.mut,
                selectedBackgroundColor: BrandColors.goldDark,
                selectedForegroundColor: Colors.white,
                side:
                    BorderSide(color: BrandColors.gold.withValues(alpha: .4)),
              ),
              segments: const [
                ButtonSegment(
                    value: false,
                    label: Text('الحركات',
                        style: TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.w700))),
                ButtonSegment(
                    value: true,
                    label: Text('التركيبات',
                        style: TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.w700))),
              ],
              selected: {_prosTab},
              onSelectionChanged: (v) => setState(() => _prosTab = v.first),
            ),
          IconButton(
            key: const Key('tr2-detail-close'),
            icon: const Icon(Icons.close_rounded, size: 18),
            color: BrandColors.mut,
            tooltip: 'إغلاق',
            onPressed: () => setState(() => _sel = null),
          ),
        ]),
        const SizedBox(height: 8),
        if (isClinic && _prosTab)
          TreasuryProsTable(
            groups: prosGrouped(s, clinic, doctorPct),
            doctorPct: doctorPct,
            month: s.month,
            clinic: clinic,
          )
        else
          TreasuryMovesTable(
            title: sel == 'exp' ? 'مصروفات الشهر' : 'حركات $title',
            subtitle: s.month,
            rows: rows,
            showService: isClinic,
            originalPrint: isClinic,
            doctorPct: doctorPct,
          ),
      ],
    );
  }
}
