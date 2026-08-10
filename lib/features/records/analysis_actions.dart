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
import '../../core/utils/ar_normalize.dart' show arNorm, normPhone;
import '../../core/utils/js_compat.dart' show getCurrentDate;
import '../settings/analyses3.dart'
    show
        lastTriAnalysisDate,
        triAnalysesEnabled,
        triAnalysesPrice,
        triRepeatBlockMessage,
        triRepeatMonths;
import 'record_saver.dart' show addAnalysisToVisit;

/// م149 — فحص قاعدة تكرار التحليل لمريضٍ ما اليوم: تعيد رسالة الحجب
/// النصية أو null إن كان مسموحاً. مصدرٌ واحد لكل مسارات الإضافة.
/// م153 — [clinic] تقصر القاعدة على العيادة نفسها، و[phone] (خام —
/// يُطبَّع هنا) لاستثناء السميَّين بهاتفين صريحين مختلفين.
String? triRepeatCheck(
  WidgetRef ref, {
  String? patientId,
  required String patientName,
  String clinic = '',
  String phone = '',
}) {
  final cfg = ref.read(appConfigProvider);
  final records =
      ref.read(reposProvider).records.getAll().cast<Map<String, Object?>>();
  return triRepeatBlockMessage(
    lastDate: lastTriAnalysisDate(
      records,
      patientId: patientId,
      patientName: patientName,
      clinic: clinic,
      phone: normPhone(phone),
      normalize: arNorm,
    ),
    today: getCurrentDate(),
    repeatMonths: triRepeatMonths(cfg),
  );
}

/// حوار خطأ الحجب — رسالة المواصفة النصية بزرّ إغلاقٍ واحد.
Future<void> showTriRepeatBlockedDialog(
  BuildContext context,
  String message,
) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('التحاليل الثلاثية'),
      content: Text(message, key: const Key('tri-repeat-blocked-msg')),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('حسناً'),
        ),
      ],
    ),
  );
}

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
  // م149 — قاعدة تكرار التحليل: حجبٌ برسالة المواصفة قبل سؤال الطريقة.
  // م153 — بنطاق عيادة الزيارة نفسها (والهاتف من معرّف الهوية إن وُجد).
  final blocked = triRepeatCheck(
    ref,
    patientId: patientId,
    patientName: patientName,
    clinic: clinic,
  );
  if (blocked != null) {
    if (context.mounted) await showTriRepeatBlockedDialog(context, blocked);
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
