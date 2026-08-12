/// م59 — الدائرة العائمة الخضراء اللامعة: تدرج أخضر العلامة (brand-g)،
/// شريطُ لمعانٍ أبيض شفاف ينزلق قطرياً عبر الدائرة كل ~2.2 ثانية،
/// وتوهج أخضر ناعم نابض حولها — بمتحكم حركة واحد (لا إعادة بناء للشاشة).
///
/// م107 — استُخرجت من شاشة ملف المريض إلى مكوّن مشترك: تستعملها بطاقة
/// المريض (الزيارة السريعة) **والصدفة** (زر «+» بالرئيسية) بهوية واحدة
/// حرفياً (طلب المالك: تطابق تام).
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class ShinyFab extends StatefulWidget {
  const ShinyFab({
    super.key,
    required this.tooltip,
    required this.onTap,
    this.icon = Icons.add_rounded, // م172 — أيقونة قابلة للتخصيص
    this.gradient, // م172 — تدرج بديل (الافتراضي أخضر العلامة حرفياً)
    this.glowColor, // م172 — لون التوهج (الافتراضي أخضر العلامة)
    this.size = 58, // م172 — نسخة مصغرة لأزرار الأشعة المتراصة
  });

  final String tooltip;
  final VoidCallback onTap;

  /// م172 — أيقونة الزر (زر الحجز/الدفعة/التصوير...) — الافتراضي «+».
  final IconData icon;

  /// م172 — تدرج بديل بهوية التطبيق (مثل الذهبي للدفعات) — null = الأخضر.
  final Gradient? gradient;

  /// م172 — لون التوهج النابض — null = أخضر العلامة (السلوك القائم).
  final Color? glowColor;

  /// م172 — قطر الدائرة (58 الافتراضي؛ 48 للأزرار المتراصة).
  final double size;

  @override
  State<ShinyFab> createState() => _ShinyFabState();
}

class _ShinyFabState extends State<ShinyFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  @override
  void initState() {
    super.initState();
    // حركة تتكرر أبداً تمنع pumpAndSettle من الاستقرار في الاختبارات
    // (تنتهي مهلته) — التكرار يعمل على الجهاز فقط، وفي الاختبارات تبقى
    // الدائرة ساكنة بشكلها النهائي (المفتاح واللمس كما هما).
    final binding = WidgetsBinding.instance.runtimeType.toString();
    if (!binding.contains('Test')) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          // اللمعان يقطع الدائرة في النصف الأول من الدورة ثم يستريح.
          final sweep = (t * 2).clamp(0.0, 1.0);
          final dx = -70 + 140 * sweep;
          // توهج نابض ناعم (جيب كامل الدورة).
          final glow = 0.35 + 0.2 * (0.5 - (t - 0.5).abs()) * 2;
          final side = widget.size;
          return Container(
            width: side,
            height: side,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: widget.gradient ?? BrandColors.brandGradient,
              border: Border.all(
                  color: const Color.fromRGBO(201, 162, 75, .35)),
              boxShadow: [
                BoxShadow(
                  color: (widget.glowColor ?? BrandColors.brand600)
                      .withValues(alpha: glow),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
                const BoxShadow(
                  color: Color.fromRGBO(10, 48, 36, .3),
                  blurRadius: 8,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: ClipOval(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // شريط اللمعان المنزلق (قطري).
                  IgnorePointer(
                    child: Transform.translate(
                      offset: Offset(dx, 0),
                      child: Transform.rotate(
                        angle: -0.6,
                        child: Container(
                          width: 22,
                          height: 90,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerRight,
                              end: Alignment.centerLeft,
                              colors: [
                                Color(0x00FFFFFF),
                                Color(0x59FFFFFF),
                                Color(0x00FFFFFF),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Material(
                    color: Colors.transparent,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: widget.onTap,
                      child: SizedBox(
                        width: side,
                        height: side,
                        child: Icon(widget.icon,
                            size: side * 27 / 58, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
