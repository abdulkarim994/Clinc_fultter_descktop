/// قسم الديون — توأم DebtsTab.vue + DebtCard.vue طبق الأصل:
/// صف بحث «بحث بالاسم أو رقم الهاتف...» مع زر قمع يفتح قائمة الأدوات
/// (سحب كل الديون + تصفية حسب العيادة)، شريط شارة «العيادة: X ✕» عند
/// التفعيل، حبوب حالة ذهبية «نشطة (N)/مسددة (N)/الكل»، أزرار طباعة لكل
/// عيادة «طباعة ديون X»، وبطاقة دين غنية: إطار أحمر/أخضر، اسم ذهبي يفتح
/// ملف المريض، شارات الحالة والتركيبات ورقاقة الهاتف، أزرار اتصال/SMS/
/// واتساب برسالة التذكير الحرفية، قائمة ⋮ (تعديل بيانات الدين/مسامحة/
/// حذف الدين)، ثلاثة أعمدة ملونة، شريط تقدم «N% مسدد»، وزرا «تسجيل
/// دفعة» و«الدفعات». النوافذ: تسجيل دفعة بمعاينة التقسيم الحرفية،
/// تعديل بيانات الدين، وسجل الدفعات (معلومات الدين + دفعات مرقمة
/// «دفعة N» أحدث أولاً + إلغاء بنقرتين خلال 3 ثوانٍ).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/data_revision.dart' show bumpDataRevision;
import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/js_compat.dart';
import '../../core/widgets/double_confirm.dart';
import '../archive/month_stats.dart' show sortByDateNewest;
import '../patients/patient_profile_screen.dart' show PatientProfileScreen;
import '../patients/patients_logic.dart' show identityOfRow;
import '../patients/patients_tab.dart' show patientSearchProvider;
import '../print/print_service.dart';
import '../print/reports.dart' show simpleTablePdf;
import '../print/treatment_tables.dart' show formatNumber;
import '../shell/app_shell.dart' show activeTabProvider;
import 'debt_actions.dart' hide JMap;
import 'installment_dialog.dart'
    show showDebtPaymentsDialog, showInstallmentDialog;
import 'finance_screen.dart' hide JMap;
import '../staff/staff_gate.dart' show gateStaff, staffAllowed;

typedef JMap = Map<String, Object?>;

/// فلتر العيادة — يضبطه قفز الخزينة («ديون معلقة» لعيادة) وقائمة القمع.
final debtsClinicFilterProvider = StateProvider<String>((ref) => '');

class DebtsSection extends ConsumerStatefulWidget {
  const DebtsSection({super.key});

  @override
  ConsumerState<DebtsSection> createState() => _DebtsSectionState();
}

class _DebtsSectionState extends ConsumerState<DebtsSection> {
  final searchCtl = TextEditingController();
  // v55 — حبوب «نشطة/مسددة/الكل» أُزيلت: المسددة تختفي تلقائياً
  // والقائمة نشطة دائماً.
  // v54 — البطاقات مطوية افتراضياً: التفاصيل تُفتح بالنقر على الرأس.

  @override
  void dispose() {
    searchCtl.dispose();
    super.dispose();
  }

  void _bump() {
    // م-إصلاح — نبض موحّد (إضافيّ وآمن): يضمن انعكاس تعديل الدفعة على
    // كل الشاشات المرتبطة فوراً. الهاتف كان يعيد البناء عند تبديل التبويب
    // أصلاً، فلا يتغير سلوكه المرئي — الفائدة للشاشات المُبقاة مركّبة.
    bumpDataRevision(ref);
    setState(() {});
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  List<JMap> _filtered(List<JMap> debts) {
    var list = debts;
    final q = searchCtl.text.trim();
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
    // v55 — المسددة تختفي تلقائياً ونهائياً من القسم (حبوب الحالة
    // أُزيلت): القائمة نشطة دائماً، وصفوف المسدد تبقى بالقاعدة تاريخاً.
    list = [for (final d in list) if (d['status'] != 'paid') d];
    // م113 — بالتاريخ أولاً (الأحدث أعلى).
    return sortByDateNewest(list);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(financeRevProvider);
    final repos = ref.watch(reposProvider);
    final debts = repos.debts.getAll();
    final cur = ref.watch(currencyProvider);
    final n = formatNumber;
    final clinicFilter = ref.watch(debtsClinicFilterProvider);

    // عيادات الديون النشطة ذات المتبقي — لزر الطباعة (حرفية الأصل).
    final debtClinics = <String>{
      for (final d in debts)
        if (d['status'] != 'paid' &&
            jsNumOr0(d['remaining']) > 0 &&
            jsTruthy(d['clinic']))
          '${d['clinic']}',
    }.toList();
    final list = _filtered(debts);

    return ListView(
      key: const Key('debts-section'),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 90),
      children: [
        // ── البحث + زر الأدوات (صف واحد مضغوط) ──
        Row(children: [
          Expanded(
            child: SizedBox(
              height: 36,
              child: TextField(
                key: const Key('debt-search'),
                controller: searchCtl,
                style: const TextStyle(fontSize: 12),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'بحث بالاسم أو رقم الهاتف...',
                  hintStyle:
                      TextStyle(fontSize: 12, color: BrandColors.strong),
                  prefixIcon: Icon(Icons.search_rounded,
                      size: 16, color: BrandColors.strong),
                  filled: true,
                  fillColor: BrandColors.surface,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                        color: BrandColors.line, width: .8),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                        color: BrandColors.line, width: .8),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: clinicFilter.isNotEmpty
                ? BrandColors.goldDark
                : BrandColors.gold.withValues(alpha: .08),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(
                  color: clinicFilter.isNotEmpty
                      ? BrandColors.goldDark
                      : BrandColors.gold.withValues(alpha: .3)),
            ),
            child: InkWell(
              key: const Key('debt-tools'),
              borderRadius: BorderRadius.circular(10),
              onTap: _openTools,
              child: SizedBox(
                width: 38,
                height: 36,
                child: Icon(Icons.filter_alt_outlined,
                    size: 16,
                    color: clinicFilter.isNotEmpty
                        ? Colors.white
                        : BrandColors.goldDark),
              ),
            ),
          ),
          // v55 — زر الطباعة الأنيق بجانب القمع (بدل صف الأزرار):
          // عيادة واحدة تطبع مباشرة، وأكثر تعرض قائمة الاختيار.
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
                key: const Key('debt-print'),
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
        const SizedBox(height: 8),

        // ── شارة فلتر العيادة ──
        if (clinicFilter.isNotEmpty) ...[
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: BrandColors.gold.withValues(alpha: .08),
              border: Border.all(
                  color: BrandColors.gold.withValues(alpha: .2)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              Text('العيادة:',
                  style:
                      TextStyle(fontSize: 11, color: BrandColors.mut)),
              const SizedBox(width: 6),
              Text(clinicFilter,
                  style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: BrandColors.goldDark)),
              const Spacer(),
              InkWell(
                key: const Key('debt-clinic-clear'),
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
          const SizedBox(height: 8),
        ],

        // v55 — حبوب «نشطة/مسددة/الكل» وصف أزرار الطباعة أُزيلا:
        // المسددة تختفي تلقائياً، والطباعة صارت أيقونة بجانب القمع.

        // ── الفراغ / البطاقات ──
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 56),
            child: Opacity(
              opacity: .35,
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
          )
        else ...[
          // م110 — الجدول (بأسلوب جدول دخل اليوم): رأس ثم صفوف.
          _debtHeaderRow(),
          for (var i = 0; i < list.length; i++) _debtRow(list[i], i, n),
        ],
      ],
    );
  }

  // v55 — _filterPill أُزيلت مع حبوب الحالة (المسددة تختفي تلقائياً).

  /// v55 — طباعة الديون من زر الرأس: عيادة واحدة تطبع مباشرة،
  /// وأكثر من عيادة تعرض قائمة اختيار (نفس بانية التقرير حرفياً).
  Future<void> _printMenu(List<String> clinics, String cur) async {
    if (clinics.length == 1) {
      _printClinicDebts(clinics.single, cur);
      return;
    }
    final v = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('طباعة ديون عيادة',
            style:
                TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
        children: [
          for (final c in clinics)
            SimpleDialogOption(
              key: Key('debt-print-$c'),
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

  /// قائمة الأدوات (القمع): سحب كل الديون + تصفية حسب العيادة.
  Future<void> _openTools() async {
    final cfg = ref.read(appConfigProvider);
    final clinics = cfg['clinics'] is List
        ? [for (final c in cfg['clinics'] as List) '$c']
        : <String>[];
    final current = ref.read(debtsClinicFilterProvider);
    final v = await showMenu<String>(
      context: context,
      position: const RelativeRect.fromLTRB(0, 150, 60, 0),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      items: [
        PopupMenuItem(
          key: const Key('debt-pull'),
          value: 'pull',
          child: const Row(children: [
            Icon(Icons.download_rounded, size: 15),
            SizedBox(width: 8),
            Text('سحب كل الديون', style: TextStyle(fontSize: 12.5)),
          ]),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          enabled: false,
          height: 30,
          child: Text('تصفية حسب العيادة:',
              style: TextStyle(fontSize: 11, color: BrandColors.mut)),
        ),
        PopupMenuItem(
          key: const Key('debt-cf-all'),
          value: 'cf:',
          child: Row(children: [
            Icon(
                current.isEmpty
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                size: 15,
                color: current.isEmpty
                    ? BrandColors.goldDark
                    : BrandColors.mut2),
            const SizedBox(width: 8),
            const Text('الكل', style: TextStyle(fontSize: 12.5)),
          ]),
        ),
        for (final c in clinics)
          PopupMenuItem(
            key: Key('debt-cf-$c'),
            value: 'cf:$c',
            child: Row(children: [
              Icon(
                  current == c
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  size: 15,
                  color: current == c
                      ? BrandColors.goldDark
                      : BrandColors.mut2),
              const SizedBox(width: 8),
              Text(c, style: const TextStyle(fontSize: 12.5)),
            ]),
          ),
      ],
    );
    if (!mounted || v == null) return;
    if (v == 'pull') {
      // توأم loadAllDebts — سحب لقطة الخادم عبر دورة المزامنة اليدوية.
      ref.read(syncUiProvider.notifier).manualSync();
      _snack('جارٍ سحب الديون من الخادم...');
    } else if (v.startsWith('cf:')) {
      ref.read(debtsClinicFilterProvider.notifier).state =
          v.substring(3);
      setState(() {});
    }
  }

  // ─────────────────────── بطاقة الدين التوأم ───────────────────────

  // ═══ م110 — جدول الديون (بأسلوب جدول دخل اليوم) ═══
  //   الأعمدة: التاريخ | الاسم (وتحته نوع العلاج • طريقة الدفع) |
  //   العيادة | الإجمالي | المتبقي | زر دفعة/سجل. الضغط المطول أو النقر
  //   اليميني يفتح ورقة الخيارات بكل وظائف البطاقة القديمة بلا نقصان
  //   (بطاقة v54 المطوية استُبدلت بالجدول بطلب المالك).

  static const _dxDate = 14,
      _dxName = 30,
      _dxClinic = 16,
      _dxTot = 15,
      _dxRem = 15;

  Widget _debtHeaderRow() {
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
        h('التاريخ', _dxDate),
        h('الاسم', _dxName),
        h('العيادة', _dxClinic),
        h('الإجمالي', _dxTot),
        h('المتبقي', _dxRem),
        const SizedBox(width: 34),
      ]),
    );
  }

  Widget _debtRow(JMap d, int i, String Function(Object?) n) {
    final id = '${d['id']}';
    final paid = d['status'] == 'paid';
    final name = '${d['name'] ?? ''}';
    final total = jsNumOr0(jsOr(d['totalAmount'], d['total']));
    final rem = jsNumOr0(d['remaining']);
    final service = '${d['service'] ?? ''}'.trim();
    final payWay = '${d['payment'] ?? ''}'.trim();
    // السطر الفرعي تحت الاسم: نوع العلاج • طريقة الدفع (يوفر عمودين).
    final sub = [
      if (d['type'] == 'prosthetic' && service.isEmpty) 'تركيبات',
      if (service.isNotEmpty) service,
      if (payWay.isNotEmpty && payWay != 'دين') payWay,
    ].join(' • ');
    final date = '${d['date'] ?? ''}';

    return GestureDetector(
      onLongPress: () => _openDebtMenu(d),
      onSecondaryTapUp: (_) => _openDebtMenu(d),
      behavior: HitTestBehavior.opaque,
      child: Container(
        key: Key('debt-card-$id'),
        decoration: BoxDecoration(
          color: paid
              ? const Color.fromRGBO(46, 125, 90, .05)
              : (i.isOdd ? const Color(0x06000000) : null),
          border: const Border(
              bottom: BorderSide(color: Color(0x11000000), width: .5)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 6),
        child: Row(children: [
          Expanded(
            flex: _dxDate,
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
            flex: _dxName,
            child: InkWell(
              key: Key('debt-name-$id'),
              // م89/م90 — عيادة الصف نفسه + هويته: لا خطف لسميٍّ آخر.
              onTap: () => _goPatient(name,
                  clinic: '${d['clinic'] ?? ''}',
                  identity: identityOfRow(d)),
              // م116 — توسيط الاسم وسطره الفرعي تحت رأس العمود مباشرة.
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
                            fontSize: 9, color: BrandColors.strong)),
                ],
              ),
            ),
          ),
          Expanded(
            flex: _dxClinic,
            child: Text('${d['clinic'] ?? ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10, color: BrandColors.mut)),
          ),
          Expanded(
            flex: _dxTot,
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
            flex: _dxRem,
            child: Text(n(rem),
                maxLines: 1,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 10.8,
                    fontWeight: FontWeight.w800,
                    color: rem > 0 ? BrandColors.red : BrandColors.mut,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ),
          // زر الدفعة (وللمسدد: سجل الدفعات) — الإجراء الأكثر تكراراً.
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
                key: Key('debt-pay-$id'),
                onTap: () {
                  // م119 — تسجيل الدفعة يتطلب صلاحيتها؛ السجل للعرض.
                  if (!paid && !gateStaff(context, 'debts.pay')) return;
                  paid ? _openPayPopup(d) : _openInstallmentDialog(d);
                },
                child: Icon(
                    paid
                        ? Icons.receipt_long_rounded
                        : Icons.payments_rounded,
                    size: 16,
                    color:
                        paid ? BrandColors.green : BrandColors.goldDark),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  /// م110 — ورقة خيارات الدين (ضغط مطول/نقر يميني): كل وظائف البطاقة
  /// القديمة + الدفعات، بنفس المسارات حرفياً.
  Future<void> _openDebtMenu(JMap d) async {
    final n = formatNumber;
    final paid = d['status'] == 'paid';
    final name = '${d['name'] ?? ''}';
    final phone = '${d['phone'] ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '');
    final total = jsNumOr0(jsOr(d['totalAmount'], d['total']));
    final paidAmt = jsNumOr0(d['paidAmount']);
    final pct = total > 0
        ? ((paidAmt / total) * 100).round().clamp(0, 100)
        : 0;

    Widget item({
      required IconData icon,
      required String label,
      Color? color,
      required VoidCallback onTap,
    }) =>
        ListTile(
          dense: true,
          leading:
              Icon(icon, size: 20, color: color ?? BrandColors.goldDark),
          title: Text(label,
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: color ?? BrandColors.ink)),
          onTap: onTap,
        );

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: BrandColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (sheetCtx) => SafeArea(
        child: SingleChildScrollView(
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
                      borderRadius: BorderRadius.circular(4)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: BrandColors.brandText)),
                    const SizedBox(height: 2),
                    Text(
                        'الإجمالي ${n(total)} • المدفوع ${n(paidAmt)} • '
                        'متبقٍ ${n(jsNumOr0(d['remaining']))} • $pct٪ مسدد',
                        style: TextStyle(
                            fontSize: 11, color: BrandColors.mut)),
                  ],
                ),
              ),
              Divider(height: 1, color: BrandColors.line),
              if (!paid && staffAllowed('debts.pay'))
                item(
                  icon: Icons.payments_rounded,
                  label: 'تسجيل دفعة',
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _openInstallmentDialog(d);
                  },
                ),
              item(
                icon: Icons.receipt_long_rounded,
                label: paid ? 'عرض سجل الدفعات' : 'الدفعات',
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _openPayPopup(d);
                },
              ),
              // م121 + م-تكافؤ — فصل التواصل عن عرض الرقم (قرار المالك):
              // صلاحية patients.phones تحجب **رؤية** الرقم في القوائم
              // والطباعة فقط؛ أزرار التواصل (واتساب/اتصال/رسالة) متاحة
              // دائماً — فإخفاء الرقم لا يمنع الموظف من التواصل.
              if (phone.isNotEmpty) ...[
                item(
                  icon: Icons.chat_rounded,
                  label: 'تذكير واتساب',
                  color: const Color(0xFF25D366),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    launchUrl(Uri.parse(_debtWaLink(d)),
                        mode: LaunchMode.externalApplication);
                  },
                ),
                item(
                  icon: Icons.call_rounded,
                  label: 'اتصال',
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    // م128 — تعقيم الهاتف (كبقية المسارات) قبل tel:.
                    launchUrl(Uri.parse(
                        'tel:${phone.replaceAll(RegExp(r'[^0-9+]'), '')}'));
                  },
                ),
                item(
                  icon: Icons.sms_rounded,
                  label: 'رسالة نصية',
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    launchUrl(Uri.parse(_smsLink(d)));
                  },
                ),
              ],
              if (staffAllowed('patients.view'))
              item(
                icon: Icons.person_rounded,
                label: 'فتح ملف المريض',
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _goPatient(name,
                      clinic: '${d['clinic'] ?? ''}',
                      identity: identityOfRow(d));
                },
              ),
              if (staffAllowed('debts.manage'))
              item(
                icon: Icons.edit_rounded,
                label: 'تعديل بيانات الدين',
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _openEditDialog(d);
                },
              ),
              if (!paid && staffAllowed('debts.manage'))
                item(
                  icon: Icons.volunteer_activism_rounded,
                  label: 'مسامحة بالمبلغ المتبقي',
                  color: BrandColors.orange,
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _forgive(d);
                  },
                ),
              if (staffAllowed('debts.manage'))
              item(
                icon: Icons.delete_rounded,
                label: 'حذف الدين',
                color: BrandColors.red,
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _confirmDelete(d);
                },
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────── الروابط والارتباطات ───────────────────────

  /// فتح ملف المريض من تبويب الديون.
  ///
  /// م89 — إصلاح القفز لبطاقة العيادة الخطأ عند تشابه الأسماء: [clinic] هي
  /// عيادة **صفّ الدين المنقور نفسه**، وهي المصدر الموثوق (الظاهر أمام
  /// المستخدم). كان الحلّ سابقاً يُعيد استنتاج العيادة بمسح كل الديون
  /// والتوقّف عند أوّل تطابقٍ بالاسم — فيخطف سميٌّ في عيادةٍ أخرى الوجهةَ.
  /// حين تُمرَّر عيادةٌ صريحة نستعملها مباشرةً؛ والمسح بالاسم يبقى مسارَ
  /// احتياطٍ لمن لا سياق عيادةٍ له فقط (بيانات قديمة بلا عيادة).
  ///
  /// م90 — [identity] هوية صفّ الدين (هاتفه): تفرّق السميّين داخل العيادة
  /// الواحدة. شاشةُ الملف تُهملها تلقائياً إن لم تكن المجموعة منقسمة.
  void _goPatient(String name, {String clinic = '', String identity = ''}) {
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
    if (clinic.isEmpty) {
      for (final p in repos.prosthetics.getAll()) {
        if ('${p['name'] ?? ''}' == name && jsTruthy(p['clinic'])) {
          clinic = '${p['clinic']}';
          break;
        }
      }
    }
    if (clinic.isNotEmpty) {
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => PatientProfileScreen(
              patientName: name, clinic: clinic, identity: identity)));
    } else {
      // لا عيادة معروفة — تبويب السجلات مع تعبئة البحث (حرفية الأصل).
      ref.read(patientSearchProvider.notifier).state = name;
      ref.read(activeTabProvider.notifier).state = 'clinics';
    }
  }

  /// رسالة تذكير الدين للواتساب — حرفية DebtCard.debtWaLink.
  String _debtWaLink(JMap d) {
    final waPhone = '${d['phone'] ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '');
    if (waPhone.isEmpty) return '#';
    final center = ref.read(centerNameProvider);
    final cur = ref.read(currencyProvider);
    final remaining = formatNumber(jsNumOr0(d['remaining']));
    final bar = '━' * 15;
    final msg = Uri.encodeComponent('\u{1F3E5} *$center*\n$bar\n'
        '\u{1F4CB} *تذكير بالمبلغ المتبقي*\n\n'
        'السلام عليكم\nعزيزنا/عزيزتنا *${d['name'] ?? ''}*\n\n'
        'نود تذكيركم بالمبلغ المتبقي:\n'
        '\u{1F4B0} المبلغ المتبقي: *$remaining $cur*\n\n'
        'نرجو التواصل معنا لتسوية المبلغ.\n\n$bar\n'
        '*$center* \u{1F9B7}');
    return 'https://wa.me/$waPhone?text=$msg';
  }

  /// رسالة تذكير الدين القصيرة — حرفية DebtCard.smsLink.
  String _smsLink(JMap d) {
    final waPhone = '${d['phone'] ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '');
    if (waPhone.isEmpty) return '#';
    final center = ref.read(centerNameProvider);
    final cur = ref.read(currencyProvider);
    final remaining = formatNumber(jsNumOr0(d['remaining']));
    final body = Uri.encodeComponent(
        '$center: تذكير بالمبلغ المتبقي ${d['name'] ?? ''} - $remaining $cur. '
        'نرجو التواصل لتسوية المبلغ.');
    return 'sms:$waPhone?body=$body';
  }

  // ─────────────────────── نافذة تسجيل دفعة ───────────────────────

  /// v33 — النافذة استُخرجت إلى الوحدة المشتركة installment_dialog
  /// (يستدعيها ملف المريض أيضاً — طريقة واحدة حرفياً في المكانين).
  Future<void> _openInstallmentDialog(JMap debt) async {
    final outcome = await showInstallmentDialog(context, ref, debt);
    if (outcome == null) return;
    _bump();
    _snack(outcome.isFull ? 'تم سداد الدين بالكامل!' : 'تم تسجيل الدفعة');
  }


  // ─────────────────────── نافذة تعديل الدين ───────────────────────

  Future<void> _openEditDialog(JMap d) async {
    final cur = ref.read(currencyProvider);
    final nameCtl = TextEditingController(text: '${d['name'] ?? ''}');
    final phoneCtl = TextEditingController(text: '${d['phone'] ?? ''}');
    final notesCtl = TextEditingController(text: '${d['notes'] ?? ''}');
    final originalTotal = jsNumOr0(jsOr(d['totalAmount'], d['total']));
    final totalCtl =
        TextEditingController(text: originalTotal.toStringAsFixed(0));
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
                    key: const Key('edit-debt-name'),
                    controller: nameCtl,
                    decoration:
                        const InputDecoration(labelText: 'اسم المريض')),
                TextField(
                  key: const Key('edit-debt-total'),
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
                    key: const Key('edit-debt-phone'),
                    controller: phoneCtl,
                    keyboardType: TextInputType.phone,
                    decoration:
                        const InputDecoration(labelText: 'رقم الهاتف')),
                TextField(
                    key: const Key('edit-debt-notes'),
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
                  key: const Key('edit-debt-save'),
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
      total: jsNumOr0(totalCtl.text) > 0 ? jsNumOr0(totalCtl.text) : null,
    );
    _bump();
    _snack('تم التحديث');
  }

  // ─────────────────────── نافذة سجل الدفعات ───────────────────────

  /// v34 — النافذة استُخرجت إلى الوحدة المشتركة installment_dialog
  /// (يستدعيها ملف المريض أيضاً — شكل وسلوك واحد في المكانين).
  Future<void> _openPayPopup(JMap debtRow) => showDebtPaymentsDialog(
        context,
        ref,
        debtRow,
        // م89+م90 — الحوار يمرّر عيادة الدين وهويته (هاتفه) مع الاسم.
        onOpenPatient: (name, clinic, identity) =>
            _goPatient(name, clinic: clinic, identity: identity),
        onChanged: _bump,
      );

  // ─────────────────────── المسامحة والحذف ───────────────────────

  /// forgiveDebt — تأكيد مزدوج ثم الإجمالي = المدفوع فعلياً.
  Future<void> _forgive(JMap d) async {
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

  /// حذف بالتأكيد المزدوج ذي العداد — يحترم dcConfirm.debtOn/debtDur.
  Future<void> _confirmDelete(JMap d) async {
    final cfg = ref.read(appConfigProvider);
    final ok = await confirmDelete(
      context,
      config: cfg,
      type: 'debt',
      title: 'حذف سجل الدين نهائياً؟',
      msg:
          'المريض: ${d['name'] ?? '—'}\nسيتم حذف الدين + السجل الأصلي + كل الدفعات نهائياً.',
    );
    if (!ok) return;
    deleteDebtCascade(ref.read(reposProvider), '${d['id']}');
    _bump();
    _snack('تم حذف الدين والسجل الأصلي وكل الدفعات');
  }

  // ─────────────────────── طباعة ديون عيادة ───────────────────────

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
      ..sort((a, b) => '${a['name'] ?? ''}'.compareTo('${b['name'] ?? ''}'));
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
        // م127 — الهاتف محجوب بالشاشة فيُحجب بالطباعة أيضاً.
        staffAllowed('patients.phones') ? '${jsOr(d['phone'], '—')}' : '—',
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
