/// م-تكافؤ — نافذة «تفاصيل الدفع» للصف مختلط الطريقة (كاش + تحويل معاً).
///
///  تُستدعى من أيقونة المعلومات بجانب طرق الدفع في صف الدفتر — على
///  الهاتف وسطح المكتب سواء — فتعرض قيمة كل طريقة والمجموع. عرضٌ صرف:
///  لا تعديل ولا أثر على البيانات.
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'home_logic.dart' show LedgerRow;

/// تنسيق رقم مختصر (فواصل آلاف بلا كسور صفرية).
String _n(num v) {
  final isInt = v == v.roundToDouble();
  final s = isInt ? v.toInt().toString() : v.toStringAsFixed(2);
  return s.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]},',
  );
}

Color _methodColor(String m) => m == 'تحويل'
    ? const Color(0xFF2563EB)
    : m == 'كاش'
        ? BrandColors.green
        : BrandColors.goldDark;

/// يعرض نافذة تفاصيل أجزاء الدفع لصفٍّ مختلط.
Future<void> showLedgerPayBreakdown(BuildContext context, LedgerRow row) {
  final parts = row.payParts.entries.toList();
  num total = 0;
  for (final e in parts) {
    total += e.value;
  }
  return showDialog<void>(
    context: context,
    builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        key: const Key('pay-breakdown'),
        backgroundColor: BrandColors.paper,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.payments_rounded, size: 20, color: BrandColors.goldDark),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'تفاصيل الدفع — ${row.name}',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: BrandColors.brandText,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (row.service.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  row.service,
                  style: TextStyle(fontSize: 12, color: BrandColors.mut),
                ),
              ),
            for (final e in parts)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  key: Key('pay-part-${e.key}'),
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _methodColor(e.key),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        e.key,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: BrandColors.brandText,
                        ),
                      ),
                    ),
                    Text(
                      _n(e.value),
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                        color: _methodColor(e.key),
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(height: 18),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'المجموع',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                      color: BrandColors.brandText,
                    ),
                  ),
                ),
                Text(
                  _n(total),
                  key: const Key('pay-breakdown-total'),
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w900,
                    color: BrandColors.goldDark,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    ),
  );
}

/// خلية «الدفع» للصف المختلط: الطرق رأسياً بخطٍّ أصغر + أيقونة معلومات
/// تفتح [showLedgerPayBreakdown] — تصميمٌ واحد يخدم كثافة الهاتف وجدول
/// سطح المكتب.
class MixedPayCell extends StatelessWidget {
  const MixedPayCell({super.key, required this.row, this.compact = true});

  final LedgerRow row;

  /// [compact] يضبط أحجام الهاتف (أصغر) مقابل جدول سطح المكتب.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final fs = compact ? 8.5 : 10.5;
    final amtFs = compact ? 8.0 : 10.0;
    return InkWell(
      key: Key('mixed-pay-${row.id}'),
      borderRadius: BorderRadius.circular(8),
      onTap: () => showLedgerPayBreakdown(context, row),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // م-تحسين (بلاغ المالك) — عرضٌ أوضح: كل طريقةٍ وقيمتها
                  // في سطرٍ (كاش ٣٠٠ / تحويل ٢٠٠) بدل الاسم وحده، فيُقرأ
                  // التقسيم دون فتح النافذة — وهي تبقى للمجموع والتفصيل.
                  for (final e in row.payParts.entries)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          e.key,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: fs,
                            height: 1.3,
                            fontWeight: FontWeight.w800,
                            color: _methodColor(e.key),
                          ),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          _n(e.value),
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: amtFs,
                            height: 1.3,
                            fontWeight: FontWeight.w700,
                            color: BrandColors.mut,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  if (row.kind == 'dp')
                    Text(
                      row.remaining <= 0 ? 'دفعة نهائية' : 'دفعة دين',
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: compact ? 7.5 : 9,
                        fontWeight: FontWeight.w700,
                        color: BrandColors.mut2,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 3),
            Icon(
              Icons.info_outline_rounded,
              size: compact ? 12 : 14,
              color: BrandColors.mut2,
            ),
          ],
        ),
      ),
    );
  }
}
