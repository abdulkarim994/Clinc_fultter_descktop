/// ============================================================================
///  الديون — نسخة سطح المكتب: Master/Detail
/// ============================================================================
///
///  (قرار المالك): يمين: قائمة الديون (بحث فوري + فلتر عيادة + جدول احترافي).
///  يسار: تفاصيل الدين المختار — المريض/الإجمالي/المدفوع/المتبقي +
///        جدول الأقساط/الدفعات + أزرار الأفعال الحالية.
///
///  - الفلاتر والبيانات من debts_section.dart بلا تعديل.
///  - الأفعال من debt_actions.dart وinstallment_dialog.dart بنفس البوابات.
///  - Hover ونقر يمين (نسخ الاسم، فتح التفاصيل) على صفوف الجدول.
///  - مفتاح DesktopSplitView: 'debts'.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/data_revision.dart' show bumpDataRevision;
import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/js_compat.dart';
import '../../../core/widgets/double_confirm.dart' show confirmDelete;
import '../../archive/month_stats.dart' show sortByDateNewest;
import '../../finance/debt_actions.dart' hide JMap;
import '../../finance/debts_section.dart' show debtsClinicFilterProvider;
import '../../finance/finance_screen.dart' show financeRevProvider;
import '../../finance/installment_dialog.dart'
    show showDebtPaymentsDialog, showInstallmentDialog;
import '../../finance/treasury_logic.dart' show activeInstallments;
import '../../patients/patient_profile_screen.dart' show PatientProfileScreen;
import '../../patients/patients_logic.dart' show identityOfRow;
import '../../print/print_service.dart' show loadPdfBrand, printOrSharePdf;
import '../../print/reports.dart' show simpleTablePdf;
import '../../print/treatment_tables.dart' show formatNumber;
import '../../staff/staff_gate.dart' show gateStaff, staffAllowed;
import '../widgets/context_menu.dart' show CtxItem, showDesktopContextMenu;
import '../widgets/split_view.dart' show DesktopSplitView, DetailHost;

typedef _JMap = Map<String, Object?>;

// ── شاشة الديون ──────────────────────────────────────────────────────────────

class DesktopDebtsScreen extends ConsumerStatefulWidget {
  const DesktopDebtsScreen({super.key});

  @override
  ConsumerState<DesktopDebtsScreen> createState() =>
      _DesktopDebtsScreenState();
}

class _DesktopDebtsScreenState extends ConsumerState<DesktopDebtsScreen> {
  _JMap? _selected;
  final _searchCtl = TextEditingController();

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  void _bump() {
    // م-إصلاح — نبض موحّد: يعيد بناء الرئيسية والإدخال اليومي وبطاقة
    // المريض وكل الشاشات المرتبطة فوراً بعد أي تعديل دين/دفعة.
    bumpDataRevision(ref);
    setState(() {});
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(msg),
            duration: const Duration(milliseconds: 1400)),
      );

  /// منطق الفلترة — نفس _filtered في debts_section.dart حرفياً.
  List<_JMap> _filtered(List<_JMap> debts) {
    var list = debts;
    final q = _searchCtl.text.trim();
    if (q.isNotEmpty) {
      final qDigits = q.replaceAll(RegExp(r'[^0-9]'), '');
      list = [
        for (final d in list)
          if ('${d['name'] ?? ''}'.contains(q) ||
              (qDigits.isNotEmpty &&
                  '${d['phone'] ?? ''}'
                      .replaceAll(RegExp(r'[^0-9]'), '')
                      .contains(qDigits)))
            d,
      ];
    }
    final clinic = ref.watch(debtsClinicFilterProvider);
    if (clinic.isNotEmpty) {
      list = [for (final d in list) if (d['clinic'] == clinic) d];
    }
    list = [for (final d in list) if (d['status'] != 'paid') d];
    return sortByDateNewest(list);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(financeRevProvider);
    final repos = ref.watch(reposProvider);
    final debts = repos.debts.getAll();
    final cur = ref.watch(currencyProvider);
    final clinicFilter = ref.watch(debtsClinicFilterProvider);
    final clinics = ref.watch(clinicsProvider);
    final list = _filtered(debts);

    // تحديث الدين المختار من القاعدة لضمان الحداثة.
    _JMap? debtDetail;
    if (_selected != null) {
      final id = '${_selected!['id']}';
      for (final d in debts) {
        if ('${d['id']}' == id) {
          debtDetail = d;
          break;
        }
      }
    }

    // عيادات الديون النشطة — لزر الطباعة.
    final debtClinics = <String>{
      for (final d in debts)
        if (d['status'] != 'paid' &&
            jsNumOr0(d['remaining']) > 0 &&
            jsTruthy(d['clinic']))
          '${d['clinic']}',
    }.toList();

    final master = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // شريط البحث + فلتر
        _buildSearchBar(clinics, clinicFilter, cur, debtClinics, list.length),
        // رأس الجدول
        if (list.isNotEmpty) const _DebtHeaderRow(),
        // القائمة
        Expanded(
          child: list.isEmpty
              ? _buildEmpty()
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: list.length,
                  itemBuilder: (ctx, i) => _DebtListTile(
                    debt: list[i],
                    cur: cur,
                    index: i,
                    selected: debtDetail != null &&
                        debtDetail['id'] == list[i]['id'],
                    onTap: () => setState(() => _selected = list[i]),
                    onCopyName: () {
                      Clipboard.setData(ClipboardData(
                          text: '${list[i]['name'] ?? ''}'));
                      _snack('نُسخ الاسم');
                    },
                    onOpenDetail: () =>
                        setState(() => _selected = list[i]),
                    onPay: (d) => _openInstallmentDialog(d),
                    onHistory: (d) => _openPayPopup(d),
                  ),
                ),
        ),
      ],
    );

    Widget? detailWidget;
    if (debtDetail != null) {
      final dd = debtDetail;
      detailWidget = DetailHost(
        hostKey: 'debts-${dd['id'] ?? ''}',
        child: _DebtDetailPanel(
          debt: dd,
          cur: cur,
          records: repos.records.getAll(),
          onClose: () => setState(() => _selected = null),
          onInstallment: () => _openInstallmentDialog(dd),
          onPayHistory: () => _openPayPopup(dd),
          onEdit: () => _openEditDialog(dd),
          onForgive: () => _forgive(dd),
          onDelete: () => _confirmDelete(dd),
          onOpenPatient: (name, clinic, identity) =>
              _goPatient(name, clinic: clinic, identity: identity),
          onCopyName: () {
            Clipboard.setData(
                ClipboardData(text: '${dd['name'] ?? ''}'));
            _snack('نُسخ الاسم');
          },
        ),
      );
    }

    return DesktopSplitView(
      id: 'debts',
      emptyIcon: Icons.receipt_long_rounded,
      emptyTitle: 'اختر ديناً لعرض التفاصيل',
      emptyHint: 'اختر ديناً من القائمة لعرض تفاصيله وأقساطه',
      masterWidth: 460,
      master: master,
      detail: detailWidget,
    );
  }

  Widget _buildSearchBar(
    List<String> clinics,
    String clinicFilter,
    String cur,
    List<String> debtClinics,
    int count,
  ) {
    return Container(
      color: BrandColors.surface,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: SizedBox(
                height: 36,
                child: TextField(
                  key: const Key('desk-debt-search'),
                  controller: _searchCtl,
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'بحث بالاسم أو رقم الهاتف...',
                    hintStyle: TextStyle(
                        fontSize: 12, color: BrandColors.mut2),
                    prefixIcon: Icon(Icons.search_rounded,
                        size: 16, color: BrandColors.mut2),
                    filled: true,
                    fillColor: BrandColors.surface2,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          BorderSide(color: BrandColors.line, width: .8),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          BorderSide(color: BrandColors.line, width: .8),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _DebtClinicFilter(
              clinics: clinics,
              selected: clinicFilter,
              onChanged: (v) =>
                  ref.read(debtsClinicFilterProvider.notifier).state = v,
            ),
            if (debtClinics.isNotEmpty) ...[
              const SizedBox(width: 8),
              Material(
                color: BrandColors.gold.withValues(alpha: .08),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                      color: BrandColors.gold.withValues(alpha: .3)),
                ),
                child: InkWell(
                  key: const Key('desk-debt-print'),
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _printMenu(debtClinics, cur),
                  child: const SizedBox(
                    width: 38,
                    height: 36,
                    child: Icon(Icons.print_rounded,
                        size: 16, color: BrandColors.goldDark),
                  ),
                ),
              ),
            ],
          ]),
          if (clinicFilter.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: BrandColors.gold.withValues(alpha: .08),
                border: Border.all(
                    color: BrandColors.gold.withValues(alpha: .2)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                Text('العيادة:',
                    style: TextStyle(
                        fontSize: 11, color: BrandColors.mut)),
                const SizedBox(width: 6),
                Text(clinicFilter,
                    style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: BrandColors.goldDark)),
                const Spacer(),
                InkWell(
                  key: const Key('desk-debt-clinic-clear'),
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => ref
                      .read(debtsClinicFilterProvider.notifier)
                      .state = '',
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: BrandColors.ink.withValues(alpha: .06),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('✕',
                        style: TextStyle(
                            fontSize: 11, color: BrandColors.mut)),
                  ),
                ),
              ]),
            ),
          ],
          const SizedBox(height: 6),
          Text('$count دين نشط',
              style: TextStyle(fontSize: 11, color: BrandColors.mut2)),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 56),
        child: Opacity(
          opacity: .4,
          child: Column(children: [
            const Icon(Icons.paid_outlined,
                size: 54, color: BrandColors.gold),
            const SizedBox(height: 12),
            Text('لا توجد ديون',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: BrandColors.ink)),
          ]),
        ),
      ),
    );
  }

  // ── الأفعال ─────────────────────────────────────────────────────────────────

  Future<void> _openInstallmentDialog(_JMap debt) async {
    final outcome = await showInstallmentDialog(context, ref, debt);
    if (outcome == null) return;
    _bump();
    _snack(outcome.isFull ? 'تم سداد الدين بالكامل!' : 'تم تسجيل الدفعة');
  }

  Future<void> _openPayPopup(_JMap debtRow) => showDebtPaymentsDialog(
        context,
        ref,
        debtRow,
        onOpenPatient: (name, clinic, identity) =>
            _goPatient(name, clinic: clinic, identity: identity),
        onChanged: _bump,
      );

  /// توأم _openEditDialog في debts_section.dart.
  Future<void> _openEditDialog(_JMap d) async {
    final cur = ref.read(currencyProvider);
    final nameCtl = TextEditingController(text: '${d['name'] ?? ''}');
    final phoneCtl = TextEditingController(text: '${d['phone'] ?? ''}');
    final notesCtl = TextEditingController(text: '${d['notes'] ?? ''}');
    final originalTotal = jsNumOr0(jsOr(d['totalAmount'], d['total']));
    final totalCtl = TextEditingController(
        text: originalTotal.toStringAsFixed(0));
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final changed = jsNumOr0(totalCtl.text) > 0 &&
              jsNumOr0(totalCtl.text) != originalTotal;
          return AlertDialog(
            title: const Text('تعديل بيانات الدين',
                style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: BrandColors.goldDark)),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    key: const Key('desk-edit-debt-name'),
                    controller: nameCtl,
                    decoration: const InputDecoration(
                        labelText: 'اسم المريض')),
                TextField(
                  key: const Key('desk-edit-debt-total'),
                  controller: totalCtl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                      labelText: 'المبلغ الإجمالي ($cur)'),
                  onChanged: (_) => setDialogState(() {}),
                ),
                if (changed)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                          '⚠ سيتم إعادة حساب المتبقي تلقائياً',
                          style: TextStyle(
                              fontSize: 11.5,
                              color: BrandColors.orange)),
                    ),
                  ),
                TextField(
                    key: const Key('desk-edit-debt-phone'),
                    controller: phoneCtl,
                    keyboardType: TextInputType.phone,
                    decoration:
                        const InputDecoration(labelText: 'رقم الهاتف')),
                TextField(
                    key: const Key('desk-edit-debt-notes'),
                    controller: notesCtl,
                    maxLines: 2,
                    decoration:
                        const InputDecoration(labelText: 'ملاحظات')),
              ]),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('إلغاء')),
              FilledButton(
                  key: const Key('desk-edit-debt-save'),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('حفظ')),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    editDebt(
      ref.read(reposProvider),
      ref.read(appConfigProvider),
      '${d['id']}',
      name: nameCtl.text,
      phone: phoneCtl.text,
      notes: notesCtl.text,
      total:
          jsNumOr0(totalCtl.text) > 0 ? jsNumOr0(totalCtl.text) : null,
    );
    _bump();
    _snack('تم التحديث');
  }

  /// توأم _forgive في debts_section.dart.
  Future<void> _forgive(_JMap d) async {
    final cfg = ref.read(appConfigProvider);
    final cur = ref.read(currencyProvider);
    final ok = await confirmDelete(
      context,
      config: cfg,
      type: 'debt',
      title: 'مسامحة بالمبلغ المتبقي؟',
      msg: 'المريض: ${d['name'] ?? '—'}\n'
          'المتبقي: ${jsNumOr0(d['remaining'])}\n'
          'سيتم تعديل الإجمالي ليعكس المدفوع فعلياً.',
    );
    if (!ok) return;
    final newTotal = forgiveDebt(
        ref.read(reposProvider), ref.read(appConfigProvider), '${d['id']}');
    if (newTotal == null) return;
    _bump();
    _snack(
        'تم مسامحة المريض — الإجمالي الآن: ${formatNumber(newTotal)} $cur');
  }

  /// توأم _confirmDelete في debts_section.dart.
  Future<void> _confirmDelete(_JMap d) async {
    final cfg = ref.read(appConfigProvider);
    final ok = await confirmDelete(
      context,
      config: cfg,
      type: 'debt',
      title: 'حذف سجل الدين نهائياً؟',
      msg: 'المريض: ${d['name'] ?? '—'}\n'
          'سيتم حذف الدين + السجل الأصلي + كل الدفعات نهائياً.',
    );
    if (!ok) return;
    deleteDebtCascade(ref.read(reposProvider), '${d['id']}');
    setState(() => _selected = null);
    _bump();
    _snack('تم حذف الدين والسجل الأصلي وكل الدفعات');
  }

  /// توأم _goPatient في debts_section.dart.
  void _goPatient(String name,
      {String clinic = '', String identity = ''}) {
    if (name.isEmpty) return;
    final repos = ref.read(reposProvider);
    if (clinic.isEmpty) {
      for (final d in repos.debts.getAll()) {
        if ('${d['name'] ?? ''}' == name && jsTruthy(d['clinic'])) {
          clinic = '${d['clinic']}';
          break;
        }
      }
    }
    if (clinic.isEmpty) {
      for (final r in repos.records.getAll()) {
        if ('${r['name'] ?? ''}' == name && jsTruthy(r['clinic'])) {
          clinic = '${r['clinic']}';
          break;
        }
      }
    }
    if (clinic.isNotEmpty && mounted) {
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => PatientProfileScreen(
              patientName: name, clinic: clinic, identity: identity)));
    }
  }

  // ── الطباعة ─────────────────────────────────────────────────────────────────

  Future<void> _printMenu(List<String> clinics, String cur) async {
    if (clinics.length == 1) {
      _printClinicDebts(clinics.single, cur);
      return;
    }
    final v = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('طباعة ديون عيادة',
            style: TextStyle(
                fontSize: 13.5, fontWeight: FontWeight.w800)),
        children: [
          for (final c in clinics)
            SimpleDialogOption(
              key: Key('desk-debt-print-$c'),
              onPressed: () => Navigator.pop(context, c),
              child: Row(children: [
                const Icon(Icons.print_rounded,
                    size: 14, color: BrandColors.goldDark),
                const SizedBox(width: 8),
                Text(c, style: const TextStyle(fontSize: 12.5)),
              ]),
            ),
        ],
      ),
    );
    if (!mounted || v == null) return;
    _printClinicDebts(v, cur);
  }

  Future<void> _printClinicDebts(String clinic, String cur) async {
    final n = formatNumber;
    final debts = ref
        .read(reposProvider)
        .debts
        .getAll()
        .where((d) =>
            d['clinic'] == clinic &&
            d['status'] != 'paid' &&
            jsNumOr0(d['remaining']) > 0)
        .toList()
      ..sort((a, b) =>
          '${a['name'] ?? ''}'.compareTo('${b['name'] ?? ''}'));
    if (debts.isEmpty) {
      _snack('لا توجد ديون متبقية لهذه العيادة');
      return;
    }
    num totalRem = 0;
    var idx = 0;
    final rows = <List<String>>[];
    for (final d in debts) {
      final rem = jsNumOr0(d['remaining']);
      totalRem += rem;
      rows.add([
        '${++idx}',
        '${d['name'] ?? '—'}',
        staffAllowed('patients.phones')
            ? '${jsOr(d['phone'], '—')}'
            : '—',
        '${jsOr(d['service'], '—')}',
        n(jsNumOr0(jsOr(d['totalAmount'], d['total']))),
        n(jsNumOr0(d['paidAmount'])),
        n(rem),
      ]);
    }
    final fonts = await loadPdfBrand(ref);
    final bytes = await simpleTablePdf(
      fonts,
      title: 'الديون المتبقية — $clinic',
      subtitle: '${debts.length} مدين · ${getCurrentDate()}',
      headers: const [
        '#', 'اسم المريض', 'رقم الهاتف', 'الخدمة',
        'الإجمالي', 'المدفوع', 'المتبقي',
      ],
      rows: rows,
      totRow: ['', 'المجموع', '', '', '', '', '${n(totalRem)} $cur'],
    );
    final msg = await printOrSharePdf(
        ref.read(dbDirProvider), bytes, 'debts_$clinic.pdf');
    if (mounted) _snack(msg);
  }
}

// ── فلتر العيادة ─────────────────────────────────────────────────────────────

class _DebtClinicFilter extends StatelessWidget {
  const _DebtClinicFilter({
    required this.clinics,
    required this.selected,
    required this.onChanged,
  });

  final List<String> clinics;
  final String selected;
  final void Function(String) onChanged;

  @override
  Widget build(BuildContext context) {
    final active = selected.isNotEmpty;
    return MenuAnchor(
      builder: (ctx, ctl, _) => Material(
        color: active
            ? BrandColors.goldDark
            : BrandColors.gold.withValues(alpha: .08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
              color: active
                  ? BrandColors.goldDark
                  : BrandColors.gold.withValues(alpha: .3)),
        ),
        child: InkWell(
          key: const Key('desk-debt-clinic-filter'),
          borderRadius: BorderRadius.circular(10),
          onTap: () => ctl.isOpen ? ctl.close() : ctl.open(),
          child: SizedBox(
            width: 38,
            height: 36,
            child: Icon(Icons.filter_alt_outlined,
                size: 16,
                color:
                    active ? Colors.white : BrandColors.goldDark),
          ),
        ),
      ),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(BrandColors.surface),
        shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12))),
      ),
      menuChildren: [
        MenuItemButton(
          key: const Key('desk-debt-cf-all'),
          onPressed: () => onChanged(''),
          leadingIcon: Icon(
              selected.isEmpty
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              size: 15,
              color: BrandColors.goldDark),
          child: const Text('الكل', style: TextStyle(fontSize: 12.5)),
        ),
        for (final c in clinics)
          MenuItemButton(
            key: Key('desk-debt-cf-$c'),
            onPressed: () => onChanged(c),
            leadingIcon: Icon(
                selected == c
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                size: 15,
                color: BrandColors.goldDark),
            child: Text(c, style: const TextStyle(fontSize: 12.5)),
          ),
      ],
    );
  }
}

// ── رأس جدول الديون ──────────────────────────────────────────────────────────

class _DebtHeaderRow extends StatelessWidget {
  const _DebtHeaderRow();

  @override
  Widget build(BuildContext context) {
    Widget h(String s, int f) => Expanded(
        flex: f,
        child: Text(s,
            maxLines: 1,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: Colors.white)));
    return Container(
      decoration: BoxDecoration(
        color: BrandColors.brand600,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(10)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      child: Row(children: [
        h('التاريخ', 14),
        h('الاسم', 30),
        h('العيادة', 16),
        h('الإجمالي', 15),
        h('المتبقي', 15),
        const SizedBox(width: 34),
      ]),
    );
  }
}

// ── صف الدين في القائمة ──────────────────────────────────────────────────────

class _DebtListTile extends StatefulWidget {
  const _DebtListTile({
    required this.debt,
    required this.cur,
    required this.index,
    required this.selected,
    required this.onTap,
    required this.onCopyName,
    required this.onOpenDetail,
    required this.onPay,
    required this.onHistory,
  });

  final _JMap debt;
  final String cur;
  final int index;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onCopyName;
  final VoidCallback onOpenDetail;
  final void Function(_JMap) onPay;
  final void Function(_JMap) onHistory;

  @override
  State<_DebtListTile> createState() => _DebtListTileState();
}

class _DebtListTileState extends State<_DebtListTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final n = formatNumber;
    final d = widget.debt;
    final id = '${d['id']}';
    final paid = d['status'] == 'paid';
    final name = '${d['name'] ?? ''}';
    final total = jsNumOr0(jsOr(d['totalAmount'], d['total']));
    final rem = jsNumOr0(d['remaining']);
    final service = '${d['service'] ?? ''}'.trim();
    final payWay = '${d['payment'] ?? ''}'.trim();
    final sub = [
      if (d['type'] == 'prosthetic' && service.isEmpty) 'تركيبات',
      if (service.isNotEmpty) service,
      if (payWay.isNotEmpty && payWay != 'دين') payWay,
    ].join(' • ');
    final date = '${d['date'] ?? ''}';

    final bg = widget.selected
        ? BrandColors.gold.withValues(alpha: .10)
        : _hovered
            ? BrandColors.surface2
            : widget.index.isOdd
                ? const Color(0x06000000)
                : null;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onSecondaryTapUp: (details) => showDesktopContextMenu(
          context,
          details.globalPosition,
          [
            CtxItem('نسخ الاسم',
                icon: Icons.copy_rounded, onTap: widget.onCopyName),
            CtxItem('فتح التفاصيل',
                icon: Icons.info_outline_rounded,
                onTap: widget.onOpenDetail),
          ],
        ),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          key: Key('desk-debt-card-$id'),
          decoration: BoxDecoration(
            color: bg,
            border: Border(
              bottom: const BorderSide(
                  color: Color(0x11000000), width: .5),
              right: widget.selected
                  ? BorderSide(
                      color: BrandColors.gold, width: 2.5)
                  : BorderSide.none,
            ),
          ),
          padding: const EdgeInsets.symmetric(
              vertical: 7, horizontal: 6),
          child: Row(children: [
            Expanded(
              flex: 14,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(date,
                    maxLines: 1,
                    style: TextStyle(
                        fontSize: 9.5,
                        height: 1.1,
                        color: BrandColors.ink,
                        fontFeatures: const [
                          FontFeature.tabularFigures()
                        ])),
              ),
            ),
            Expanded(
              flex: 30,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: paid
                              ? BrandColors.mut
                              : BrandColors.brandText)),
                  if (sub.isNotEmpty)
                    Text(sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 9, color: BrandColors.mut2)),
                ],
              ),
            ),
            Expanded(
              flex: 16,
              child: Text('${d['clinic'] ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 10, color: BrandColors.mut)),
            ),
            Expanded(
              flex: 15,
              child: Text(n(total),
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 10.8,
                      fontWeight: FontWeight.w800,
                      color: BrandColors.ink,
                      fontFeatures: const [
                        FontFeature.tabularFigures()
                      ])),
            ),
            Expanded(
              flex: 15,
              child: Text(n(rem),
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 10.8,
                      fontWeight: FontWeight.w800,
                      color: rem > 0
                          ? BrandColors.red
                          : BrandColors.mut,
                      fontFeatures: const [
                        FontFeature.tabularFigures()
                      ])),
            ),
            // زر الدفعة / سجل
            SizedBox(
              width: 34,
              height: 30,
              child: Material(
                color: paid
                    ? BrandColors.green.withValues(alpha: .10)
                    : BrandColors.gold.withValues(alpha: .14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9)),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: Key('desk-debt-pay-$id'),
                  onTap: () {
                    if (!paid &&
                        !gateStaff(context, 'debts.pay')) {
                      return;
                    }
                    paid
                        ? widget.onHistory(d)
                        : widget.onPay(d);
                  },
                  child: Icon(
                      paid
                          ? Icons.receipt_long_rounded
                          : Icons.payments_rounded,
                      size: 16,
                      color: paid
                          ? BrandColors.green
                          : BrandColors.goldDark),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── لوحة تفاصيل الدين ────────────────────────────────────────────────────────

class _DebtDetailPanel extends StatelessWidget {
  const _DebtDetailPanel({
    required this.debt,
    required this.cur,
    required this.records,
    required this.onClose,
    required this.onInstallment,
    required this.onPayHistory,
    required this.onEdit,
    required this.onForgive,
    required this.onDelete,
    required this.onOpenPatient,
    required this.onCopyName,
  });

  final _JMap debt;
  final String cur;
  final List<_JMap> records;
  final VoidCallback onClose;
  final VoidCallback onInstallment;
  final VoidCallback onPayHistory;
  final VoidCallback onEdit;
  final VoidCallback onForgive;
  final VoidCallback onDelete;
  final void Function(String, String, String) onOpenPatient;
  final VoidCallback onCopyName;

  @override
  Widget build(BuildContext context) {
    final n = formatNumber;
    final d = debt;
    final paid = d['status'] == 'paid';
    final name = '${d['name'] ?? ''}';
    final total = jsNumOr0(jsOr(d['totalAmount'], d['total']));
    final paidAmt = jsNumOr0(d['paidAmount']);
    final rem = jsNumOr0(d['remaining']);
    final pct = total > 0
        ? ((paidAmt / total) * 100).round().clamp(0, 100)
        : 0;
    final clinic = '${d['clinic'] ?? ''}'.trim();
    final service = '${d['service'] ?? ''}'.trim();
    final phone = '${d['phone'] ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '');
    final notes = '${d['notes'] ?? ''}'.trim();
    final date = '${d['date'] ?? ''}';
    final insts = activeInstallments(d);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // رأس
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: paid
                    ? BrandColors.green.withValues(alpha: .12)
                    : BrandColors.red.withValues(alpha: .10),
                border: Border.all(
                    color: paid
                        ? BrandColors.green.withValues(alpha: .35)
                        : BrandColors.red.withValues(alpha: .3)),
              ),
              child: Icon(
                paid
                    ? Icons.check_circle_rounded
                    : Icons.hourglass_bottom_rounded,
                size: 22,
                color: paid ? BrandColors.green : BrandColors.red,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: onCopyName,
                    child: Text(name,
                        key: const Key('desk-debt-detail-name'),
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: BrandColors.goldDark)),
                  ),
                  const SizedBox(height: 2),
                  Text('$date · ${paid ? 'مسدد' : 'نشط'}',
                      style: TextStyle(
                          fontSize: 11.5, color: BrandColors.mut2)),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 18),
              color: BrandColors.mut,
              tooltip: 'إغلاق',
              onPressed: onClose,
            ),
          ]),
          const SizedBox(height: 14),

          // الأعمدة الثلاثة
          Row(children: [
            _AmountCell(
                label: 'الإجمالي',
                value: '${n(total)} $cur',
                color: BrandColors.ink),
            const SizedBox(width: 6),
            _AmountCell(
                label: 'المدفوع',
                value: '${n(paidAmt)} $cur',
                color: BrandColors.green),
            const SizedBox(width: 6),
            _AmountCell(
                label: 'المتبقي',
                value: '${n(rem)} $cur',
                color: rem > 0 ? BrandColors.red : BrandColors.green),
          ]),
          const SizedBox(height: 10),

          // شريط التقدم
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: pct / 100,
                  minHeight: 7,
                  backgroundColor:
                      BrandColors.red.withValues(alpha: .15),
                  valueColor:
                      AlwaysStoppedAnimation(BrandColors.green),
                ),
              ),
              const SizedBox(height: 3),
              Text('$pct٪ مسدد',
                  textAlign: TextAlign.end,
                  style: TextStyle(
                      fontSize: 10.5, color: BrandColors.mut2)),
            ],
          ),
          const SizedBox(height: 12),

          // معلومات إضافية
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: BrandColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: BrandColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (clinic.isNotEmpty) ...[
                  _FieldRow(label: 'العيادة', value: clinic),
                  const SizedBox(height: 6),
                ],
                if (service.isNotEmpty) ...[
                  _FieldRow(label: 'الخدمة', value: service),
                  const SizedBox(height: 6),
                ],
                if (staffAllowed('patients.phones') &&
                    phone.isNotEmpty) ...[
                  _FieldRow(label: 'الهاتف', value: phone),
                  const SizedBox(height: 6),
                ],
                if (notes.isNotEmpty)
                  _FieldRow(
                      label: 'ملاحظات',
                      value: notes,
                      color: BrandColors.mut),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // أزرار الأفعال
          _buildActionButtons(context, d, paid, phone),
          const SizedBox(height: 16),

          // جدول الأقساط
          if (insts.isNotEmpty) ...[
            Text('الأقساط والدفعات',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: BrandColors.brandText)),
            const SizedBox(height: 6),
            _InstallmentsTable(insts: insts, cur: cur),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButtons(
      BuildContext context, _JMap d, bool paid, String phone) {
    Widget btn({
      required IconData icon,
      required String label,
      required VoidCallback onTap,
      Color? bg,
      Color? fg,
    }) =>
        Expanded(
          child: FilledButton.icon(
            onPressed: onTap,
            icon: Icon(icon, size: 15),
            label: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label,
                  style: const TextStyle(fontSize: 11.5)),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: bg ?? BrandColors.brand600,
              foregroundColor: fg ?? Colors.white,
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // صف 1: تسجيل دفعة + الدفعات
        Row(children: [
          if (!paid && staffAllowed('debts.pay')) ...[
            btn(
              icon: Icons.payments_rounded,
              label: 'تسجيل دفعة',
              onTap: onInstallment,
              bg: BrandColors.goldDark,
            ),
            const SizedBox(width: 6),
          ],
          btn(
            icon: Icons.receipt_long_rounded,
            label: paid ? 'سجل الدفعات' : 'الدفعات',
            onTap: onPayHistory,
            bg: BrandColors.surface2,
            fg: BrandColors.brandText,
          ),
        ]),
        const SizedBox(height: 6),
        // صف 2: ملف المريض + واتساب
        Row(children: [
          if (staffAllowed('patients.view'))
            btn(
              icon: Icons.person_rounded,
              label: 'ملف المريض',
              onTap: () => onOpenPatient(
                '${d['name'] ?? ''}',
                '${d['clinic'] ?? ''}',
                identityOfRow(d),
              ),
              bg: BrandColors.surface2,
              fg: BrandColors.brandText,
            ),
          // م-تكافؤ — التواصل متاح دائماً (صلاحية patients.phones تحجب
          // رؤية الرقم في العمود والتفاصيل فقط، لا القدرة على التواصل).
          if (phone.isNotEmpty) ...[
            const SizedBox(width: 6),
            btn(
              icon: Icons.chat_rounded,
              label: 'واتساب',
              onTap: () {
                final msg = Uri.encodeComponent(
                    'تذكير بالمبلغ المتبقي ${d['name'] ?? ''} - ${formatNumber(jsNumOr0(d['remaining']))}');
                launchUrl(
                  Uri.parse('https://wa.me/$phone?text=$msg'),
                  mode: LaunchMode.externalApplication,
                );
              },
              bg: const Color(0xFF25D366),
            ),
          ],
        ]),
        // صف 3: إدارة
        if (staffAllowed('debts.manage')) ...[
          const SizedBox(height: 6),
          Row(children: [
            btn(
              icon: Icons.edit_rounded,
              label: 'تعديل',
              onTap: onEdit,
              bg: BrandColors.surface2,
              fg: BrandColors.brandText,
            ),
            if (!paid) ...[
              const SizedBox(width: 6),
              btn(
                icon: Icons.volunteer_activism_rounded,
                label: 'مسامحة',
                onTap: onForgive,
                bg: BrandColors.orange.withValues(alpha: .15),
                fg: BrandColors.orange,
              ),
            ],
            const SizedBox(width: 6),
            btn(
              icon: Icons.delete_rounded,
              label: 'حذف',
              onTap: onDelete,
              bg: BrandColors.red.withValues(alpha: .12),
              fg: BrandColors.red,
            ),
          ]),
        ],
      ],
    );
  }
}

// ── خانة مبلغ ────────────────────────────────────────────────────────────────

class _AmountCell extends StatelessWidget {
  const _AmountCell({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: .22)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(label,
                maxLines: 1,
                style:
                    TextStyle(fontSize: 9.5, color: BrandColors.mut2)),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value,
                  maxLines: 1,
                  key: label == 'المتبقي'
                      ? const Key('desk-debt-detail-remaining')
                      : null,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                      color: color,
                      fontFeatures: const [
                        FontFeature.tabularFigures()
                      ])),
            ),
          ],
        ),
      ),
    );
  }
}

// ── صف حقل المعلومات ─────────────────────────────────────────────────────────

class _FieldRow extends StatelessWidget {
  const _FieldRow(
      {required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 72,
          child: Text(label,
              style:
                  TextStyle(fontSize: 11, color: BrandColors.mut2)),
        ),
        Expanded(
          child: Text(value,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color ?? BrandColors.ink)),
        ),
      ],
    );
  }
}

// ── جدول الأقساط ─────────────────────────────────────────────────────────────

class _InstallmentsTable extends StatelessWidget {
  const _InstallmentsTable({required this.insts, required this.cur});

  final List<_JMap> insts;
  final String cur;

  @override
  Widget build(BuildContext context) {
    final n = formatNumber;

    Widget h(String s, int flex) => Expanded(
        flex: flex,
        child: Text(s,
            maxLines: 1,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: Colors.white)));

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: BrandColors.line),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            color: BrandColors.brand700,
            padding: const EdgeInsets.symmetric(
                vertical: 7, horizontal: 6),
            child: Row(children: [
              h('#', 10),
              h('التاريخ', 25),
              h('المبلغ', 22),
              h('طريقة الدفع', 22),
            ]),
          ),
          for (var i = 0; i < insts.length; i++)
            Container(
              color: i.isOdd ? const Color(0x06000000) : null,
              padding: const EdgeInsets.symmetric(
                  vertical: 7, horizontal: 6),
              child: Row(children: [
                Expanded(
                  flex: 10,
                  child: Text('${i + 1}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: BrandColors.mut2)),
                ),
                Expanded(
                  flex: 25,
                  child: Text('${insts[i]['date'] ?? ''}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 10.5, color: BrandColors.ink)),
                ),
                Expanded(
                  flex: 22,
                  child: Text(n(jsNumOr0(insts[i]['amount'])),
                      textAlign: TextAlign.center,
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: BrandColors.green,
                          fontFeatures: const [
                            FontFeature.tabularFigures()
                          ])),
                ),
                Expanded(
                  flex: 22,
                  child: Text('${insts[i]['payment'] ?? '—'}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 10.5, color: BrandColors.mut)),
                ),
              ]),
            ),
        ],
      ),
    );
  }
}
