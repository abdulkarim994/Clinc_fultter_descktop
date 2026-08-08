/// ============================================================================
///  التخطيط المنقسم — Master/Detail لكل شاشات سطح المكتب
/// ============================================================================
///
///  (قرار المالك): القسم الأيمن قائمة دائمة الظهور (بحث/فلاتر/قائمة)،
///  والقسم الأيسر تفاصيل — فارغ عند البداية برسالة «اختر … لعرض
///  التفاصيل»، وعند اختيار عنصر تتغير التفاصيل **فقط** دون فتح صفحة
///  جديدة ودون إعادة تحميل.
///
///  - في RTL أول أبناء Row يقع على اليمين — فالقائمة الرئيسية أولاً.
///  - فاصل قابل للسحب لتغيير عرض القائمة، ويُحفظ محلياً لكل شاشة
///    عبر desktop_prefs (مفتاح `split.<id>`).
///  - التفاصيل تُغلَّف بـ Navigator متداخل عبر [DetailHost] كي تبقى أي
///    دفعات صفحات داخلية (ملف المريض يفتح شاشاته الفرعية) محصورة في
///    القسم الأيسر لا فوق الشاشة كلها.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../desktop_prefs.dart';

class DesktopSplitView extends ConsumerStatefulWidget {
  const DesktopSplitView({
    super.key,
    required this.id,
    required this.master,
    this.detail,
    this.emptyIcon = Icons.touch_app_outlined,
    this.emptyTitle = 'اختر عنصراً لعرض التفاصيل',
    this.emptyHint,
    this.masterWidth = 380,
    this.minMasterWidth = 300,
    this.maxMasterWidth = 560,
  });

  /// معرف الشاشة لحفظ عرض القائمة (مثل patients/treasury/labs).
  final String id;

  /// القسم الأيمن — القائمة الرئيسية.
  final Widget master;

  /// القسم الأيسر — التفاصيل (null = الحالة الفارغة).
  final Widget? detail;

  final IconData emptyIcon;
  final String emptyTitle;
  final String? emptyHint;

  final double masterWidth;
  final double minMasterWidth;
  final double maxMasterWidth;

  @override
  ConsumerState<DesktopSplitView> createState() => _DesktopSplitViewState();
}

class _DesktopSplitViewState extends ConsumerState<DesktopSplitView> {
  double? _width; // null ⇒ من التفضيلات/الافتراضي
  bool _dragging = false;

  double _effectiveWidth(BoxConstraints c) {
    final prefs = ref.watch(desktopPrefsProvider);
    final saved = prefs['split.${widget.id}'];
    var w = _width ??
        (saved is num ? saved.toDouble() : widget.masterWidth);
    // القائمة لا تتجاوز 45% من الشاشة مهما اتسعت.
    final maxW = [widget.maxMasterWidth, c.maxWidth * .45]
        .reduce((a, b) => a < b ? a : b);
    if (w > maxW) w = maxW;
    if (w < widget.minMasterWidth) w = widget.minMasterWidth;
    return w;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final w = _effectiveWidth(constraints);
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── القسم الأيمن (RTL): القائمة الرئيسية — ظاهرة دائماً ──
          SizedBox(width: w, child: widget.master),
          // ── الفاصل القابل للسحب ──
          MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (_) =>
                  setState(() => _dragging = true),
              onHorizontalDragUpdate: (d) {
                // RTL: السحب نحو اليسار (delta سالب) يوسّع القائمة.
                setState(() => _width = (w - d.delta.dx)
                    .clamp(widget.minMasterWidth, widget.maxMasterWidth));
              },
              onHorizontalDragEnd: (_) {
                setState(() => _dragging = false);
                if (_width != null) {
                  saveDesktopPref(ref, 'split.${widget.id}', _width);
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 7,
                color: _dragging
                    ? BrandColors.gold.withValues(alpha: .25)
                    : Colors.transparent,
                child: Center(
                  child: Container(
                    width: 1.5,
                    color: _dragging ? BrandColors.gold : BrandColors.line,
                  ),
                ),
              ),
            ),
          ),
          // ── القسم الأيسر: التفاصيل أو الحالة الفارغة ──
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: widget.detail ??
                  SplitEmptyState(
                    key: const ValueKey('split-empty'),
                    icon: widget.emptyIcon,
                    title: widget.emptyTitle,
                    hint: widget.emptyHint,
                  ),
            ),
          ),
        ],
      );
    });
  }
}

/// الحالة الفارغة للقسم الأيسر.
class SplitEmptyState extends StatelessWidget {
  const SplitEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.hint,
  });

  final IconData icon;
  final String title;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: BrandColors.brand.withValues(alpha: .06),
              border: Border.all(
                  color: BrandColors.gold.withValues(alpha: .25)),
            ),
            child: Icon(icon, size: 38, color: BrandColors.faint),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: BrandColors.mut,
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: 6),
            Text(
              hint!,
              style: TextStyle(fontSize: 12, color: BrandColors.faint),
            ),
          ],
        ],
      ),
    );
  }
}

/// مضيف تفاصيل بملاّح متداخل: أي Navigator.push داخل [child] يبقى
/// داخل القسم الأيسر (لا يغطي الشاشة). مفتاح [hostKey] يعيد بناء
/// الملاح عند تغيّر العنصر المختار فيتصفّر عمق التنقل.
class DetailHost extends StatelessWidget {
  const DetailHost({super.key, required this.hostKey, required this.child});

  final Object hostKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Navigator(
        key: ValueKey('detail-host-$hostKey'),
        onGenerateRoute: (settings) => MaterialPageRoute(
          settings: settings,
          builder: (_) => child,
        ),
      ),
    );
  }
}
