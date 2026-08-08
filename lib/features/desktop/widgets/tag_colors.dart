/// ============================================================================
///  وسوم ألوان الصفوف — لوحة الألوان الخمسة وعناصر عرضها واختيارها
/// ============================================================================
///
///  (قرار المالك): «إضافة إمكانية تمييز أي سجل بلون: أحمر، أصفر، أخضر،
///  أزرق، بنفسجي — الوسم يبقى محفوظاً». الحفظ في desktop_prefs.dart
///  (app.config['desktopRowTags'] المُزامَن)، وهنا العرض فقط.
///
///  الألوان مشتقة من عائلة الهوية (أحمر/أخضر العلامة) مع ثلاثة ألوان
///  وظيفية متوازنة معها — مشبعة بما يكفي لتمييز فوري، وهادئة بما يكفي
///  كي لا تكسر وقار اللوحة الزمردية/الذهبية.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// وسم لون واحد.
class RowTag {
  const RowTag(this.id, this.label, this.color);
  final String id;
  final String label;
  final Color color;
}

/// اللوحة المعتمدة — الترتيب ترتيب طلب المالك.
const kRowTags = <RowTag>[
  RowTag('red', 'أحمر', Color(0xFFC0392B)), // BrandColors.red
  RowTag('yellow', 'أصفر', Color(0xFFD9A514)),
  RowTag('green', 'أخضر', Color(0xFF1E7A52)), // BrandColors.green
  RowTag('blue', 'أزرق', Color(0xFF2563EB)),
  RowTag('purple', 'بنفسجي', Color(0xFF7C3AED)),
];

RowTag? rowTagOf(String? id) {
  if (id == null || id.isEmpty) return null;
  for (final t in kRowTags) {
    if (t.id == id) return t;
  }
  return null;
}

/// صبغة خلفية الصف الموسوم (خافتة كي يبقى النص بتباينه الكامل).
Color? rowTagTint(String? id) {
  final t = rowTagOf(id);
  if (t == null) return null;
  return t.color.withValues(alpha: BrandColors.darkMode ? .16 : .09);
}

/// شريط حافة البداية للصف الموسوم.
Widget rowTagStripe(String? id, {double width = 3, double height = 22}) {
  final t = rowTagOf(id);
  return AnimatedContainer(
    duration: const Duration(milliseconds: 150),
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: t?.color ?? Colors.transparent,
      borderRadius: BorderRadius.circular(2),
    ),
  );
}

/// صف نقاط الألوان للاختيار (يُستعمل داخل قوائم السياق والحوارات).
/// [current] الوسم الحالي، [onPick] يستقبل المعرف أو null للإزالة.
class RowTagPicker extends StatelessWidget {
  const RowTagPicker({super.key, this.current, required this.onPick});

  final String? current;
  final ValueChanged<String?> onPick;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final t in kRowTags)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Tooltip(
              message: t.label,
              child: InkWell(
                key: Key('row-tag-${t.id}'),
                customBorder: const CircleBorder(),
                onTap: () => onPick(t.id),
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: t.color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: current == t.id
                          ? BrandColors.ink
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: current == t.id
                      ? const Icon(Icons.check_rounded,
                          size: 14, color: Colors.white)
                      : null,
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Tooltip(
            message: 'إزالة الوسم',
            child: InkWell(
              key: const Key('row-tag-clear'),
              customBorder: const CircleBorder(),
              onTap: () => onPick(null),
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: BrandColors.faint),
                ),
                child: Icon(Icons.close_rounded,
                    size: 14, color: BrandColors.mut2),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
