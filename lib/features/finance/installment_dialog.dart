/// ============================================================================
///  نافذة «تسجيل دفعة» الموحّدة — v33
/// ============================================================================
///
///  استُخرجت نافذة قسم الديون (توأم Installment Modal) **حرفياً** إلى
///  وحدة مشتركة واحدة يستدعيها قسم الديون بالمالية وملف المريض بالسجلات
///  معاً — فطريقة تسجيل الدفعة واحدة في المكانين تماماً:
///    • المتبقي + «المعمل المتبقي» وتحذير الخصم لديون التركيبات.
///    • قيمة الدفعة + منتقي التاريخ + قائمة **طريقة الدفع** من إعدادات
///      الحساب (كانت نافذة الملف تثبّت «كاش» بالكود — علة هذه المرحلة).
///    • معاينة التقسيم الحرفية (للمعمل / ربح الطبيب / ربح العيادة).
///  التنفيذ عبر payDebtInstallment نفسه (اللقطات والأقساط وسجل الدفعة).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/js_compat.dart';
import '../patients/patients_logic.dart' show navIdentityOf;
import '../print/treatment_tables.dart' show formatNumber;
import '../staff/staff_gate.dart' show staffAllowed;
import '../records/day_close_store.dart' show confirmClosedDayWrite;
import '../records/income_day_dialog.dart' show askIncomeDay;
import 'debt_actions.dart' hide JMap;
import 'treasury_logic.dart' show installmentsForDisplay;

typedef JMap = Map<String, Object?>;

/// نتيجة النافذة: null = إلغاء؛ وإلا نجاح مع علم السداد الكامل.
class InstallmentOutcome {
  const InstallmentOutcome({required this.isFull});
  final bool isFull;
}

/// يفتح نافذة تسجيل الدفعة الموحّدة وينفّذ الدفعة عند التأكيد.
/// يعيد null عند الإلغاء، أو النتيجة عند النجاح. أخطاء التحقق
/// (كدفعة أكبر من المتبقي) تُعرض snack ويُعاد null.
Future<InstallmentOutcome?> showInstallmentDialog(
  BuildContext context,
  WidgetRef ref,
  JMap debt,
) async {
  final cfg = ref.read(appConfigProvider);
  final cur = ref.read(currencyProvider);
  final payments = cfg['payments'] is List
      ? [for (final p in cfg['payments'] as List) '$p']
      : <String>['كاش'];
  final amountCtl = TextEditingController();
  var date = getCurrentDate();
  var payment = payments.isNotEmpty ? payments.first : 'كاش';
  final n = formatNumber;
  final ip = debt['type'] == 'prosthetic';
  final labRem = ip
      ? (jsNumOr0(debt['labValue']) - jsNumOr0(debt['labPaid']))
          .clamp(0, double.infinity)
      : 0;
  // نسبة العرض في المعاينة — العامة (حرفية قالب الأصل).
  final dpLabel = jsNumOr0(jsOr(cfg['doctorPct'], 50));

  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) {
        final amount = jsNumOr0(amountCtl.text);
        final preview =
            amount > 0 ? previewInstallment(cfg, debt, amount) : null;
        return AlertDialog(
          title: const Row(children: [
            Icon(Icons.add_circle_outline_rounded,
                size: 15, color: BrandColors.goldDark),
            SizedBox(width: 6),
            Text('تسجيل دفعة',
                style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: BrandColors.goldDark)),
          ]),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('المتبقي:',
                          style: TextStyle(
                              fontSize: 11.5, color: BrandColors.mut)),
                      Text('${n(jsNumOr0(debt['remaining']))} $cur',
                          style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w900,
                              color: BrandColors.red)),
                    ]),
                if (ip && labRem > 0) ...[
                  const SizedBox(height: 6),
                  Row(
                      mainAxisAlignment:
                          MainAxisAlignment.spaceBetween,
                      children: [
                        Text('المعمل المتبقي:',
                            style: TextStyle(
                                fontSize: 11.5,
                                color: BrandColors.mut)),
                        Text('${n(labRem)} $cur',
                            style: const TextStyle(
                                fontSize: 12,
                                color: BrandColors.orange)),
                      ]),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.only(top: 6),
                    decoration: BoxDecoration(
                      border: Border(
                          top: BorderSide(
                              color: BrandColors.line, width: .6)),
                    ),
                    child: const Text('⚠ تُخصم أولاً من المعمل ثم الربح',
                        style: TextStyle(
                            fontSize: 11.5, color: BrandColors.orange)),
                  ),
                ],
                const SizedBox(height: 10),
                TextField(
                  key: const Key('inst-amount'),
                  controller: amountCtl,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'قيمة الدفعة'),
                  onChanged: (_) => setDialogState(() {}),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const Key('inst-date'),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: DateTime.parse(date),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2035),
                        );
                        if (picked != null) {
                          setDialogState(() => date =
                              '${picked.year.toString().padLeft(4, '0')}-'
                              '${picked.month.toString().padLeft(2, '0')}-'
                              '${picked.day.toString().padLeft(2, '0')}');
                        }
                      },
                      child: Text(date,
                          style: const TextStyle(fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: const Key('inst-payment'),
                      initialValue: payment,
                      items: [
                        for (final p in payments)
                          DropdownMenuItem(value: p, child: Text(p)),
                      ],
                      onChanged: (v) =>
                          setDialogState(() => payment = v ?? payment),
                      decoration:
                          const InputDecoration(labelText: 'الدفع'),
                    ),
                  ),
                ]),
                if (preview != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: BrandColors.surface2,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('معاينة:',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: BrandColors.mut)),
                        const SizedBox(height: 6),
                        if (ip) ...[
                          if (preview.toLab > 0)
                            _pvRow('للمعمل:', '${n(preview.toLab)} $cur',
                                BrandColors.orange),
                          if (preview.toProfit > 0) ...[
                            _pvRow(
                                'ربح الطبيب ($dpLabel%):',
                                '${n(preview.docShare)} $cur',
                                BrandColors.green),
                            _pvRow(
                                'ربح العيادة (${100 - dpLabel}%):',
                                '${n(preview.clinShare)} $cur',
                                BrandColors.green),
                          ] else
                            const Text('كل الدفعة للمعمل فقط',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: BrandColors.orange)),
                        ] else
                          _pvRow('قيمة الدفعة:', '${n(amount)} $cur',
                              BrandColors.green),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('إلغاء')),
            FilledButton(
                key: const Key('inst-confirm'),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('تأكيد الدفعة')),
          ],
        );
      },
    ),
  );
  if (ok != true) return null;
  // م101 — دفعة بتاريخ غير اليوم: أين يُحسب الإيراد؟ (الإلغاء = لا دفع).
  if (!context.mounted) return null;
  final incomeDay = await askIncomeDay(context, date);
  if (incomeDay == null) return null;
  // م104 — يوم الاحتساب مقفول؟ تنبيه ومتابعة بالتأكيد فقط.
  if (!context.mounted) return null;
  if (!await confirmClosedDayWrite(
      context, ref.read(reposProvider).settings, incomeDay)) {
    return null;
  }
  try {
    final result = payDebtInstallment(
      ref.read(reposProvider),
      ref.read(appConfigProvider),
      debt,
      amount: jsNumOr0(amountCtl.text),
      date: date,
      payment: payment,
      incomeDate: incomeDay,
    );
    return InstallmentOutcome(isFull: result.isFull);
  } on ArgumentError catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${e.message}')));
    }
    return null;
  }
}

Widget _pvRow(String label, String value, Color color) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                overflow: TextOverflow.ellipsis,
                style:
                    TextStyle(fontSize: 11, color: BrandColors.mut)),
          ),
          // م41 — القيمة تتقلص رشيقاً عند الضيق بدل الفيضان.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: color)),
          ),
        ],
      ),
    );


/// ============================================================================
///  نافذة «سجل الدفعات» الموحّدة — v34 (توأم Payment History Popup حرفياً)
/// ============================================================================
///
///  معلومات الدين (شارة الحالة + المريض + الهاتف + الكلي/المدفوع/المتبقي)
///  + شريط التقدم بنسبة السداد + الدفعات المرقمة أحدث أولاً + **إلغاء
///  دفعة بنقرتين خلال 3 ثوانٍ** (cancelDebtInstallment: يحذف القسط وسجل
///  دفعته ويعيد حساب المدفوع/المتبقي/الحالة). يستدعيها قسم الديون
///  بالمالية وملف المريض بالسجلات — شكل وسلوك واحد في المكانين.
Future<void> showDebtPaymentsDialog(
  BuildContext context,
  WidgetRef ref,
  JMap debtRow, {
  /// فتح ملف المريض — يمررها قسم المالية؛ وفي ملف المريض تُترك null (نحن
  /// داخل الملف أصلاً) فيظهر الاسم نصاً بلا رابط.
  ///
  /// م89 — يحمل الآن **عيادة صفّ الدين المفتوح** مع الاسم، فلا يُخطَف القفزُ
  /// لسميٍّ في عيادة أخرى عند تشابه الأسماء.
  /// م90 — وهويتَه (هاتفَه) أيضاً — تفرقةُ السميّين داخل العيادة الواحدة.
  void Function(String name, String clinic, String identity)? onOpenPatient,

  /// نبضة تحديث بعد إلغاء دفعة (يمررها كل مستدعٍ بمزوداته).
  VoidCallback? onChanged,
}) async {
  final debtId = '${debtRow['id']}';
  final cur = ref.read(currencyProvider);
  final n = formatNumber;
  String? armedInstId;
  Timer? armTimer;

  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) {
        final repos = ref.read(reposProvider);
        final debt = repos.debts.getById(debtId) ?? debtRow;
        final records = repos.records.getAll();
        final insts = installmentsForDisplay(debt, records);
        final paid = debt['status'] == 'paid';
        final total = jsNumOr0(jsOr(debt['totalAmount'], debt['total']));
        final payPct = total > 0
            ? ((jsNumOr0(debt['paidAmount']) / total) * 100)
                .round()
                .clamp(0, 100)
            : 0;
        return AlertDialog(
          title: Row(children: [
            const Icon(Icons.receipt_long_rounded,
                size: 15, color: BrandColors.goldDark),
            const SizedBox(width: 6),
            Expanded(
              child: Text('سجل الدفعات — ${debt['name'] ?? ''}',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: BrandColors.goldDark)),
            ),
          ]),
          content: SizedBox(
            width: 340,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── معلومات الدين ──
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: BrandColors.surface2,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(children: [
                          const Expanded(
                            child: Text('معلومات الدين',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    color: BrandColors.brand700)),
                          ),
                          // م41 — الشارة تتقلص رشيقاً عند الضيق.
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: _payBadge(
                                paid ? 'مسدد بالكامل' : 'غير مسدد',
                                paid
                                    ? BrandColors.green
                                    : BrandColors.red),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Text('المريض:',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: BrandColors.mut)),
                              Flexible(
                                  child: onOpenPatient != null
                                  ? InkWell(
                                      key: const Key('pays-patient'),
                                      onTap: () {
                                        Navigator.pop(context);
                                        onOpenPatient(
                                            '${debt['name'] ?? ''}',
                                            '${debt['clinic'] ?? ''}',
                                            // م181 — هوية الحلّال الموروث
                                            navIdentityOf(
                                                ref.read(reposProvider),
                                                debt));
                                      },
                                      child: Text(
                                          '${debt['name'] ?? ''}',
                                          style: const TextStyle(
                                              fontSize: 12.5,
                                              fontWeight:
                                                  FontWeight.w900,
                                              color: BrandColors
                                                  .goldDark)),
                                    )
                                  : Text('${debt['name'] ?? ''}',
                                      key: const Key('pays-patient'),
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w900,
                                          color:
                                              BrandColors.goldDark))),
                            ]),
                        if (jsTruthy(debt['phone'])) ...[
                          const SizedBox(height: 4),
                          Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Text('الهاتف:',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: BrandColors.mut)),
                                // م-تكافؤ — سدّ تسريب: الرقم كان يظهر
                                // هنا بلا فحص patients.phones إطلاقاً.
                                // الرؤية بالصلاحية، والاتصال متاح دائماً
                                // (نفس فلسفة بقية الشاشات بعد الفصل).
                                InkWell(
                                  onTap: () => launchUrl(Uri.parse(
                                      'tel:${debt['phone']}')),
                                  child: Text(
                                      staffAllowed('patients.phones')
                                          ? '${debt['phone']}'
                                          : 'اتصال ☎ (الرقم محجوب)',
                                      style: const TextStyle(
                                          fontSize: 11.5,
                                          color: BrandColors.green)),
                                ),
                              ]),
                        ],
                        const SizedBox(height: 4),
                        _pvRow('المبلغ الكلي:', '${n(total)} $cur',
                            BrandColors.orange),
                        _pvRow(
                            'المدفوع:',
                            '${n(jsNumOr0(debt['paidAmount']))} $cur',
                            BrandColors.green),
                        _pvRow(
                            'المتبقي:',
                            '${n(jsNumOr0(debt['remaining']))} $cur',
                            BrandColors.red),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: SizedBox(
                            height: 8,
                            child: Stack(children: [
                              Container(
                                  color: BrandColors.line
                                      .withValues(alpha: .45)),
                              FractionallySizedBox(
                                widthFactor: payPct / 100,
                                child: Container(
                                    color: payPct >= 100
                                        ? BrandColors.green
                                        : BrandColors.gold),
                              ),
                            ]),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Center(
                          child: Text('$payPct% مسدد',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: BrandColors.mut2)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // ── قائمة الدفعات ──
                  if (insts.isNotEmpty) ...[
                    Text('الدفعات (${insts.length})',
                        style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: BrandColors.brand700)),
                    const SizedBox(height: 6),
                    for (final inst in insts)
                      Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: BrandColors.surface,
                          border: Border.all(
                              color: BrandColors.brand
                                  .withValues(alpha: .08)),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                    '${n(jsNumOr0(inst['amount']))} $cur',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: BrandColors.green)),
                                const SizedBox(height: 2),
                                Text(
                                    '${inst['date'] ?? ''} — ${inst['payment'] ?? ''}',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: BrandColors.mut2)),
                              ],
                            ),
                          ),
                          Text('دفعة ${jsNumOr0(inst['seq']).toInt()}',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: BrandColors.mut)),
                          const SizedBox(width: 8),
                          Material(
                            color:
                                BrandColors.red.withValues(alpha: .06),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                  color: BrandColors.red
                                      .withValues(alpha: .18)),
                            ),
                            child: InkWell(
                              key: Key('pay-cancel-${inst['id']}'),
                              borderRadius: BorderRadius.circular(8),
                              onTap: () {
                                final instId = '${inst['id']}';
                                if (armedInstId == instId) {
                                  armTimer?.cancel();
                                  armedInstId = null;
                                  final done = cancelDebtInstallment(
                                      ref.read(reposProvider),
                                      ref.read(appConfigProvider),
                                      debtId,
                                      instId);
                                  if (done) {
                                    onChanged?.call();
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(const SnackBar(
                                            content: Text(
                                                'تم إلغاء الدفعة')));
                                  }
                                  setDialogState(() {});
                                } else {
                                  armTimer?.cancel();
                                  setDialogState(
                                      () => armedInstId = instId);
                                  armTimer = Timer(
                                      const Duration(seconds: 3), () {
                                    armedInstId = null;
                                    if (context.mounted) {
                                      setDialogState(() {});
                                    }
                                  });
                                }
                              },
                              child: SizedBox(
                                width: armedInstId == '${inst['id']}'
                                    ? 44
                                    : 28,
                                height: 28,
                                child: Center(
                                  child: armedInstId ==
                                          '${inst['id']}'
                                      ? const Text('تأكيد',
                                          style: TextStyle(
                                              fontSize: 11,
                                              fontWeight:
                                                  FontWeight.w800,
                                              color: BrandColors.red))
                                      : const Icon(
                                          Icons
                                              .delete_outline_rounded,
                                          size: 13,
                                          color: BrandColors.red),
                                ),
                              ),
                            ),
                          ),
                        ]),
                      ),
                  ] else
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(vertical: 14),
                      child: Center(
                        child: Text('لا توجد دفعات مسجلة',
                            style: TextStyle(
                                fontSize: 11.5,
                                color: BrandColors.mut2)),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                key: const Key('pays-close'),
                onPressed: () => Navigator.pop(context),
                child: const Text('إغلاق'),
              ),
            ),
          ],
        );
      },
    ),
  );
  armTimer?.cancel();
}

Widget _payBadge(String text, Color color) => Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        border: Border.all(color: color.withValues(alpha: .28)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: color)),
    );
