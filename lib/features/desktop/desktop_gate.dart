/// ============================================================================
///  بوابة واجهة سطح المكتب — نقطة الفصل الوحيدة بين نسختي الهاتف والكمبيوتر
/// ============================================================================
///
///  القاعدة (قرار المالك — Desktop UI/UX Migration):
///  «جميع التعديلات تطبق فقط على نسخة الكمبيوتر. يمنع تعديل أو التأثير على
///  نسخة الهاتف بأي شكل. يجب استخدام Responsive Breakpoints بحيث يكون لكل
///  منصة واجهتها الخاصة.»
///
///  التنفيذ: شرطان معاً —
///  1) منصة سطح مكتب (Windows/Linux/macOS عبر defaultTargetPlatform —
///     يحترم override الاختبارات، وقيمته في اختبارات الودجت android
///     افتراضياً فلا يتأثر أيٌّ من اختبارات الهاتف الحالية).
///  2) عرض النافذة ≥ [kDesktopBreakpoint] — تصغير النافذة دون الحد يعيد
///     واجهة الهاتف الحالية حرفياً (استجابة حية بلا إعادة تشغيل).
///
///  كل كود سطح المكتب يعيش في lib/features/desktop/ ويستهلك نفس
///  الـ Providers والمستودعات ومنطق العمل 1:1 — لا مساس بقاعدة البيانات
///  ولا بالـ APIs ولا بأي سلوك هاتفي.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// حد الفصل المعتمد (قرار الخطة المعتمدة): 1100 بكسل منطقي.
const double kDesktopBreakpoint = 1100;

/// إجبار وضعٍ محدد في الاختبارات: true = سطح مكتب دائماً،
/// false = هاتف دائماً، null = القاعدة الطبيعية.
@visibleForTesting
bool? debugForceDesktopUi;

/// هل المنصة الحالية منصة سطح مكتب؟
bool isDesktopPlatform() => switch (defaultTargetPlatform) {
      TargetPlatform.windows ||
      TargetPlatform.linux ||
      TargetPlatform.macOS =>
        true,
      _ => false,
    };

/// القرار المركزي: هل تُعرض واجهة سطح المكتب في هذا السياق؟
///
/// يقرأ عرض النافذة عبر [MediaQuery.sizeOf] فيُعاد بناء المستمعين عند
/// تغيّر الحجم فقط (لا كامل الـ MediaQuery) — وهو ما يحقق «Responsive
/// Breakpoints» حيّة بين الواجهتين.
bool isDesktopUi(BuildContext context) {
  if (debugForceDesktopUi != null) return debugForceDesktopUi!;
  if (!isDesktopPlatform()) return false;
  return MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;
}
