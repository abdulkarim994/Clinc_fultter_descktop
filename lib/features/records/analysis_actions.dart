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
import '../patients/patients_logic.dart' show IdentityIndex;
import '../settings/analyses3.dart'
    show
        TriGate,
        lastTriAnalysisHit,
        triAnalysesEnabled,
        triAnalysesPrice,
        triRepeatGate,
        triRepeatMonths;
import 'record_saver.dart' show addAnalysisToVisit;

/// م149 — فحص قاعدة تكرار التحليل لمريضٍ ما اليوم: تعيد رسالة الحجب
/// النصية أو null إن كان مسموحاً. مصدرٌ واحد لكل مسارات الإضافة.
/// م153 — [clinic] تقصر القاعدة على العيادة نفسها، و[phone] (خام —
/// يُطبَّع هنا) لاستثناء السميَّين بهاتفين صريحين مختلفين.
/// م187 — البوابة الكاملة: قرارٌ بدرجتين (حجب/تحذير) بدل رسالةٍ واحدة.
/// النطاق **المركز كله** (لا العيادة) والهوية **بالهاتف** — انظر
/// `lastTriAnalysisHit`. [clinic] لم تبقَ مؤثّرة وأُبقيت للتوافق.
TriGate triRepeatGateFor(
  WidgetRef ref, {
  String? patientId,
  required String patientName,
  String clinic = '',
  String phone = '',
}) {
  final cfg = ref.read(appConfigProvider);
  final repos = ref.read(reposProvider);
  final records = repos.records.getAll().cast<Map<String, Object?>>();
  // م189 — حلّال الهوية الموروث: صفُّ تحليلٍ قديمٍ بلا عمود هاتف يرث هاتف
  // زيارته الأصل (`analysisOf`) — فتعود الهوية مؤكَّدة ويحلّ الحجبُ/السماحُ
  // الصحيح مكان التحذير الأعمى.
  final idx = IdentityIndex(
    records,
    repos.prosthetics.getAll().cast<Map<String, Object?>>(),
    repos.debts.getAll().cast<Map<String, Object?>>(),
  );
  return triRepeatGate(
    hit: lastTriAnalysisHit(
      records,
      patientId: patientId,
      patientName: patientName,
      // م189 — هاتف الطرف الحالي أيضاً: الممرَّر صراحةً وإلا الموروث من
      // صفّ الزيارة عبر معرّفه (المسار الأكثر استعمالاً لا يمرّره).
      phone: phone,
      normalize: arNorm,
      normPhone: normPhone,
      phoneOfRow: idx.phoneOf,
    ),
    today: getCurrentDate(),
    repeatMonths: triRepeatMonths(cfg),
  );
}

/// توافقٌ خلفي: رسالة **الحجب القاطع** وحدها (null للمسموح والتحذير).
String? triRepeatCheck(
  WidgetRef ref, {
  String? patientId,
  required String patientName,
  String clinic = '',
  String phone = '',
}) {
  final g = triRepeatGateFor(ref,
      patientId: patientId,
      patientName: patientName,
      clinic: clinic,
      phone: phone);
  return g.isBlocked ? g.message : null;
}

/// م187 — تشغيل البوابة أمام المستخدم: يعيد true إن جاز المضي.
///  • مسموح ⇒ true بلا أي حوار.
///  • حجب ⇒ حوارُ رفضٍ بزرّ واحد ⇒ false.
///  • تحذير ⇒ حوارٌ بخيارَين، فيمضي إن اختار «متابعة على مسؤوليتي».
Future<bool> passTriGate(
  BuildContext context,
  WidgetRef ref, {
  String? patientId,
  required String patientName,
  String clinic = '',
  String phone = '',
}) async {
  final g = triRepeatGateFor(ref,
      patientId: patientId,
      patientName: patientName,
      clinic: clinic,
      phone: phone);
  if (g.isAllowed) return true;
  if (g.isBlocked) {
    if (context.mounted) await showTriRepeatBlockedDialog(context, g.message);
    return false;
  }
  if (!context.mounted) return false;
  return await showTriRepeatWarnDialog(context, g.message) ?? false;
}

/// حوار التحذير (هوية غير مؤكَّدة): يمضي بموافقةٍ صريحة.
Future<bool?> showTriRepeatWarnDialog(
  BuildContext context,
  String message,
) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const Key('tri-repeat-warn'),
      title: const Text('تنبيه — اسم مكرر'),
      content: Text(message.replaceAll('**', ''),
          key: const Key('tri-repeat-warn-msg')),
      actions: [
        TextButton(
          key: const Key('tri-warn-cancel'),
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          key: const Key('tri-warn-proceed'),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('متابعة على مسؤوليتي'),
        ),
      ],
    ),
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
  /// م187 — هاتف المريض للبوابة: يُمرَّر من المنادي إن عرفه، وإلا يُقرأ
  /// من صفّ الزيارة نفسها (analysisOf) — فلا يبقى الفحص أعمى عن الهاتف.
  String? patientPhone,
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
  // م149 — قاعدة تكرار التحليل قبل سؤال الطريقة.
  // م187 — البوابة بدرجتيها (حجب/تحذير)، و**الهاتف يُمرَّر أخيراً**: كان
  // هذا المسار (ثلاث نقاط الجدول وبطاقة المريض) لا يمرّره إطلاقاً فيُعطَّل
  // استثناء السميَّين عملياً — وهو أكثر المسارات استعمالاً (بلاغ المالك).
  // م189 — وإن خلا عمودُ الزيارة من الهاتف: يُورَّث من معرّف هويتها أو من
  // أصلها بالحلّال — فلا يمضي الفحص أعمى ولا يُكتب صفٌّ بلا هوية (ملفٌ
  // فارغ في سجلات المريض — بلاغ المالك).
  final visitRow = repos.records.getById(analysisOf);
  final gatePhone = (patientPhone ?? '').trim().isNotEmpty
      ? patientPhone!.trim()
      : (visitRow == null
          ? ''
          : IdentityIndex(
              repos.records.getAll().cast<Map<String, Object?>>(),
              repos.prosthetics.getAll().cast<Map<String, Object?>>(),
              repos.debts.getAll().cast<Map<String, Object?>>(),
            ).phoneOf(visitRow.cast<String, Object?>()));
  if (!await passTriGate(
    context,
    ref,
    patientId: patientId,
    patientName: patientName,
    clinic: clinic,
    phone: gatePhone,
  )) {
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
    // م187 — نفس هاتف البوابة، و**التحذير مُتجاوَزٌ سلفاً**: passTriGate
    // أعلاه لم يرجع true إلا بموافقة الطبيب الصريحة، فلا يردّه الكاتب.
    phone: gatePhone,
    overrideWarn: true,
  );
  if (ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('أُضيفت التحاليل الثلاثية')),
    );
  }
  return ok;
}
