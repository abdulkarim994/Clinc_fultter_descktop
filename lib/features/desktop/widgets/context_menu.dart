/// ============================================================================
///  قائمة السياق المكتبية — زر يمين الفأرة في كل نسخة الكمبيوتر
/// ============================================================================
///
///  واجهة واحدة لكل الشاشات: عناصر {أيقونة، تسمية، فعل} مع فواصل وعناصر
///  مدمّرة (حمراء) وعنصر «وسم اللون» الجاهز. تُفتح عند موضع المؤشر
///  بمحاذاة RTL صحيحة، وتغلق بـ Esc (سلوك showMenu المدمج).
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import 'tag_colors.dart';

/// عنصر قائمة سياق.
class CtxItem {
  const CtxItem(
    this.label, {
    this.icon,
    this.onTap,
    this.destructive = false,
    this.enabled = true,
    this.keyId,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool destructive;
  final bool enabled;
  final String? keyId;

  /// فاصل.
  static const divider = CtxItem('—divider—');
  bool get isDivider => identical(this, divider) || label == '—divider—';
}

/// عنصر «وسم اللون» — صف نقاط الألوان داخل القائمة.
class CtxTagRow extends CtxItem {
  const CtxTagRow({this.current, required this.onPick})
      : super('وسم اللون');
  final String? current;
  final ValueChanged<String?> onPick;
}

/// فتح قائمة سياق عند [position] (إحداثيات عامة — من TapDownDetails
/// globalPosition أو مركز العنصر). ترجع بعد الإغلاق.
Future<void> showDesktopContextMenu(
  BuildContext context,
  Offset position,
  List<CtxItem> items,
) async {
  final overlay =
      Overlay.of(context).context.findRenderObject() as RenderBox?;
  final size = overlay?.size ?? MediaQuery.sizeOf(context);
  final entries = <PopupMenuEntry<int>>[];
  final actions = <int, VoidCallback>{};
  var i = 0;
  for (final it in items) {
    if (it.isDivider) {
      if (entries.isNotEmpty && entries.last is! PopupMenuDivider) {
        entries.add(const PopupMenuDivider(height: 6));
      }
      continue;
    }
    if (it is CtxTagRow) {
      entries.add(PopupMenuItem<int>(
        enabled: false,
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Icon(Icons.label_rounded, size: 16, color: BrandColors.mut2),
            const SizedBox(width: 8),
            Text(it.label,
                style: TextStyle(fontSize: 12, color: BrandColors.mut)),
            const SizedBox(width: 10),
            RowTagPicker(
              current: it.current,
              onPick: (c) {
                Navigator.of(context, rootNavigator: true).pop();
                it.onPick(c);
              },
            ),
          ],
        ),
      ));
      continue;
    }
    final idx = i++;
    if (it.onTap != null) actions[idx] = it.onTap!;
    entries.add(PopupMenuItem<int>(
      value: idx,
      enabled: it.enabled && it.onTap != null,
      height: 38,
      key: it.keyId == null ? null : Key('ctx-${it.keyId}'),
      child: Row(
        children: [
          if (it.icon != null) ...[
            Icon(it.icon,
                size: 17,
                color: it.destructive ? BrandColors.red : BrandColors.mut),
            const SizedBox(width: 9),
          ],
          // Flexible + ellipsis: تسميات عربية طويلة («زيارة سريعة جديدة»)
          // قد تتجاوز عرض القائمة الأقصى بضع بكسلات؛ هذا حارس تخطيطي بحت
          // لا يغيّر نصّاً ولا سلوكاً (يقصّ فقط في أضيق الحالات القصوى).
          Flexible(
            child: Text(
              it.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: it.destructive ? BrandColors.red : BrandColors.ink,
              ),
            ),
          ),
        ],
      ),
    ));
  }
  if (entries.isEmpty) return;

  final picked = await showMenu<int>(
    context: context,
    // م(RTL): الموضع من نقطة النقر نفسها — RelativeRect يحسب من الحواف.
    position: RelativeRect.fromLTRB(
      position.dx,
      position.dy,
      size.width - position.dx,
      size.height - position.dy,
    ),
    color: BrandColors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: BrandColors.line),
    ),
    elevation: 6,
    items: entries,
  );
  if (picked != null) actions[picked]?.call();
}

/// غلاف يلتقط الزر الأيمن (والضغط المطول على شاشات اللمس المكتبية)
/// ويفتح قائمة سياق يبنيها [itemsBuilder] لحظة الفتح.
class ContextMenuRegion extends StatelessWidget {
  const ContextMenuRegion({
    super.key,
    required this.child,
    required this.itemsBuilder,
    this.enabled = true,
  });

  final Widget child;
  final List<CtxItem> Function() itemsBuilder;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onSecondaryTapDown: (d) =>
          showDesktopContextMenu(context, d.globalPosition, itemsBuilder()),
      child: child,
    );
  }
}
