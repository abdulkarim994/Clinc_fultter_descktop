/// ============================================================================
///  نوافذ سطح المكتب — بديل «الشاشة الكاملة/الورقة السفلية» على الكمبيوتر
/// ============================================================================
///
///  (قرار المالك): «أي نافذة كانت Full Screen في الهاتف تتحول في
///  الكمبيوتر إلى Drawer أو Dialog مناسب».
///
///  ثلاثة مضيفات:
///  - [showDesktopDialog]  — حوار مركزي بعرضٍ مضبوط (نماذج قصيرة/تأكيدات).
///  - [showDesktopSideSheet] — درج جانبي من حافة **النهاية** (يسار RTL)
///    بارتفاع الشاشة الكامل — بديل الأوراق السفلية الطويلة (نموذج
///    الزيارة، الملفات…). يدعم Esc للإغلاق تلقائياً.
///  - [showDesktopPanel] — حوار عريض شبه‑شاشة (تقارير/معاينات).
///
///  كلها تعيد نفس Future النمط القديم فتصلح بديلاً مباشراً في فروع
///  `isDesktopUi` داخل منافذ الفتح المشتركة — دون أي تغيير على مسار
///  الهاتف.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

const _kBarrier = Color.fromRGBO(10, 48, 36, .45);

/// ترويسة موحدة لنوافذ سطح المكتب: عنوان + زر إغلاق (Esc).
class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.title, this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        gradient: BrandColors.brandGradient,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: BrandColors.goldLight,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .75),
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          Tooltip(
            message: 'إغلاق (Esc)',
            child: InkWell(
              key: const Key('desktop-sheet-close'),
              customBorder: const CircleBorder(),
              onTap: () => Navigator.of(context).maybePop(),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .08),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: const Color.fromRGBO(201, 162, 75, .2)),
                ),
                child: const Icon(Icons.close_rounded,
                    size: 18, color: BrandColors.goldLight),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// حوار مركزي بعرض مضبوط. [title] يضيف الترويسة الموحدة؛ بدونه يُعرض
/// المحتوى خاماً داخل سطح الحوار.
Future<T?> showDesktopDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  String? title,
  String? subtitle,
  double width = 560,
  double? maxHeight,
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: _kBarrier,
    builder: (ctx) {
      final h = maxHeight ?? MediaQuery.sizeOf(ctx).height * .88;
      return Dialog(
        backgroundColor: BrandColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color.fromRGBO(201, 162, 75, .25)),
        ),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width, maxHeight: h),
          child: title == null
              ? builder(ctx)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SheetHeader(title: title, subtitle: subtitle),
                    Flexible(child: builder(ctx)),
                  ],
                ),
        ),
      );
    },
  );
}

/// درج جانبي بارتفاع الشاشة من حافة النهاية (يسار في RTL) — بديل
/// الأوراق السفلية الطويلة والشاشات الكاملة ذات النماذج.
Future<T?> showDesktopSideSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  String? title,
  String? subtitle,
  double width = 520,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: 'إغلاق',
    barrierColor: _kBarrier,
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (ctx, _, _) {
      final w = width.clamp(320.0, MediaQuery.sizeOf(ctx).width * .6);
      return Align(
        // نهاية RTL = اليسار: الدرج ينزلق من الحافة المقابلة للشريط
        // الجانبي فلا يغطيه.
        alignment: AlignmentDirectional.centerEnd,
        child: SizedBox(
          width: w.toDouble(),
          height: double.infinity,
          child: Material(
            color: BrandColors.surface,
            elevation: 16,
            shadowColor: const Color.fromRGBO(10, 48, 36, .5),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (title != null)
                    _SheetHeader(title: title, subtitle: subtitle),
                  Expanded(
                    child: MediaQuery.removePadding(
                      context: ctx,
                      removeTop: true,
                      child: builder(ctx),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (ctx, anim, _, child) {
      final curved =
          CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      // انزلاق من نهاية الاتجاه (يسار RTL) مع تعتيم الخلفية.
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(-1, 0), // يسار البداية البصرية في RTL
          end: Offset.zero,
        ).animate(curved),
        textDirection: TextDirection.rtl,
        child: child,
      );
    },
  );
}

/// حوار عريض شبه‑شاشة للتقارير والمعاينات.
Future<T?> showDesktopPanel<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  String? title,
  String? subtitle,
}) {
  final size = MediaQuery.sizeOf(context);
  return showDesktopDialog<T>(
    context,
    builder: builder,
    title: title,
    subtitle: subtitle,
    width: (size.width * .82).clamp(640.0, 1280.0),
    maxHeight: size.height * .9,
  );
}
