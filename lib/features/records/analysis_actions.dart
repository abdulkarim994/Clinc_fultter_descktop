/// م147 — إجراءات «التحاليل الثلاثية» المشتركة على زيارةٍ قائمة.
///
/// نافذةٌ منبثقة صغيرة تسأل طريقة الدفع (كاش/تحويل) بزرَّي موافق/إلغاء،
/// ثم تكتب صفَّ التحليل عبر [addAnalysisToVisit] (السعر ثابتٌ من الإعدادات
/// — سلوكٌ مطابقٌ لإضافته من «زيارة جديدة»). تُستعمل من: جدول إدخال اليوم
/// (كمبيوتر/هاتف) وثلاث نقاط بطاقة المريض — مصدرٌ واحد لسلوكٍ واحد.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../settings/analyses3.dart' show triAnalysesEnabled, triAnalysesPrice;
import 'record_saver.dart' show addAnalysisToVisit;

/// نافذة اختيار طريقة الدفع للتحاليل — تعيد 'كاش' أو 'تحويل' أو null (إلغاء).
Future<String?> pickAnalysisPayment(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (ctx) {
      String pay = 'كاش';
      return StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('التحاليل الثلاثية', textAlign: TextAlign.right),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'طريقة الدفع',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: BrandColors.brandText,
                ),
              ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                key: const Key('anal-pay-picker'),
                style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: BrandColors.surface2,
                  foregroundColor: BrandColors.mut,
                  selectedBackgroundColor: BrandColors.green,
                  selectedForegroundColor: Colors.white,
                  side: BorderSide(
                    color: BrandColors.green.withValues(alpha: .40),
                  ),
                ),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'كاش', label: Text('كاش')),
                  ButtonSegment(value: 'تحويل', label: Text('تحويل')),
                ],
                selected: {pay},
                onSelectionChanged: (s) => setLocal(() => pay = s.first),
              ),
            ],
          ),
          actions: [
            TextButton(
              key: const Key('anal-pay-cancel'),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              key: const Key('anal-pay-ok'),
              onPressed: () => Navigator.pop(ctx, pay),
              child: const Text('موافق'),
            ),
          ],
        ),
      );
    },
  );
}

/// يسأل الطريقة ثم يضيف التحليل لزيارةٍ قائمة. يعيد true عند الكتابة.
/// حارسٌ مسبق: إن كانت الميزة معطّلة يخبر المستخدم ولا يفتح النافذة.
Future<bool> promptAddAnalysisToVisit(
  BuildContext context,
  WidgetRef ref, {
  required String analysisOf,
  required String patientName,
  String? patientId,
  required String clinic,
  required String date,
  String? incomeDate,
}) async {
  final repos = ref.read(reposProvider);
  final cfg = ref.read(appConfigProvider);
  if (!triAnalysesEnabled(cfg) || triAnalysesPrice(cfg) <= 0) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('فعّل «التحاليل الثلاثية» وحدّد سعرها من الإعدادات أولاً'),
        ),
      );
    }
    return false;
  }
  final pay = context.mounted ? await pickAnalysisPayment(context) : null;
  if (pay == null) return false;
  final ok = addAnalysisToVisit(
    repos,
    analysisOf: analysisOf,
    patientName: patientName,
    patientId: patientId,
    clinic: clinic,
    date: date,
    incomeDate: incomeDate,
    cfg: cfg,
    payment: pay,
  );
  if (ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('أُضيفت التحاليل الثلاثية')),
    );
  }
  return ok;
}
