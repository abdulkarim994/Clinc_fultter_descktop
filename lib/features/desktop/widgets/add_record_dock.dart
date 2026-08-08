/// ============================================================================
///  لوح «زيارة جديدة» المرسى — Desktop Bottom Dock
/// ============================================================================
///
///  (قرار المالك — عقد التصميم «ج»): بديل الدرج الجانبي الضيق على الكمبيوتر
///  بلوحٍ سفليٍّ **مرسى** يعيش داخل [DesktopShell] لا حوارٌ ولا overlay —
///  يدفع مساحة العمل للأعلى (تنكمش طبيعياً في Expanded) بدل تغطيتها،
///  ويستعيد المساحة ارتفاعها عند الإغلاق.
///
///  البنية:
///  - [addRecordDockProvider] — حالة الفتح: null مغلق، وإلا [AddRecordDockRequest]
///    الحامل لوضع التعديل (editEntry/editKind/editDebt) أو الجديد (كلها null).
///  - [AddRecordDock] — السطح المرسى: ترويسة زمردية رفيعة (مقبض سحب + عنوان
///    «زيارة جديدة»/«تعديل السجل» + زر توسيع/طي + زر إغلاق)، ثم النموذج الكامل
///    [AddRecordScreen] بتخطيطه الأفقي متعدد الأعمدة (horizontal: true) داخل
///    تمريرةٍ رأسية احتياطية.
///  - ثلاثة أوضاع ارتفاع عبر AnimatedContainer(220ms easeOutCubic):
///    مضغوط (screenH*0.34، الافتراضي) وموسّع (screenH*0.62 — تلقائياً عند
///    تفعيل الدين/التركيبات، أو يدوياً بزر التوسيع).
///
///  الحقول والمنطق والحفظ كلها في [AddRecordScreen] بلا تغيير — هذا الملف
///  غلافٌ بصري بحت (استضافة + انتقالات + ترويسة).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/theme/app_theme.dart';
import '../../records/add_record_screen.dart' show AddRecordScreen;

/// طلب فتح اللوح: التعديل يحمل السجل الأصلي ونوعه ودينه؛ الجديد كلها null.
/// كائنٌ ثابت بسيط (لا يحمل حالة قابلة للتغيير) — تبديل المرجع كافٍ لإعادة
/// بناء الشِل.
class AddRecordDockRequest {
  const AddRecordDockRequest({
    this.editEntry,
    this.editKind = 'r',
    this.editDebt,
  });

  /// وضع التعديل: السجل/التركيبة الأصلية (null = زيارة جديدة).
  final Map<String, Object?>? editEntry;

  /// نوع الأصل: r سجل، p تركيبة.
  final String editKind;

  /// دين الأصل المرتبط إن وُجد.
  final Map<String, Object?>? editDebt;

  bool get isEdit => editEntry != null;
}

/// حالة لوح «زيارة جديدة» المرسى في نسخة الكمبيوتر — null = مغلق.
/// يضبطه [openAddRecordSheet] (فرع الديسكتوب) و_newVisit/Ctrl+N، ويعيده
/// Esc/زر الإغلاق/الحفظ الناجح إلى null.
final addRecordDockProvider = StateProvider<AddRecordDockRequest?>(
  (ref) => null,
);

/// السطح المرسى نفسه — يُبنى فقط حين [addRecordDockProvider] غير null.
class AddRecordDock extends ConsumerStatefulWidget {
  const AddRecordDock({super.key, required this.request});

  final AddRecordDockRequest request;

  @override
  ConsumerState<AddRecordDock> createState() => _AddRecordDockState();
}

class _AddRecordDockState extends ConsumerState<AddRecordDock> {
  /// موسّع؟ يبدأ مضغوطاً؛ يرتفع تلقائياً عند تفعيل الدين/التركيبات (إشعار
  /// بصري بحت من النموذج) ويقلبه المستخدم بزر التوسيع.
  bool _expanded = false;

  void _close() =>
      ref.read(addRecordDockProvider.notifier).state = null;

  /// إشعار بصري من النموذج: للمحتوى أقسامٌ مفتوحة (دين/تركيبات) ⇒ ارفع اللوح.
  /// يُستدعى بعد الإطار (لا داخل build) فلا يخالف setState-during-build.
  void _onExpandedContent(bool needsRoom) {
    if (needsRoom && !_expanded && mounted) {
      setState(() => _expanded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final req = widget.request;
    final screenH = MediaQuery.sizeOf(context).height;
    // ثلاثة أوضاع: مضغوط (افتراضي) / موسّع (تلقائي عند الدين/التركيبات أو
    // يدوي). محصورٌ بحدٍّ أدنى/أقصى معقول كي لا ينهار على الشاشات القصيرة
    // ولا يبتلع الشِل على الطويلة.
    final targetH =
        (screenH * (_expanded ? 0.62 : 0.34)).clamp(220.0, screenH - 96);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      height: targetH,
      decoration: BoxDecoration(
        color: BrandColors.surface,
        border: Border(
          top: BorderSide(
            color: BrandColors.gold.withValues(alpha: .35),
            width: 1,
          ),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(10, 48, 36, .18),
            blurRadius: 18,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DockHeader(
            title: req.isEdit ? 'تعديل السجل' : 'زيارة جديدة',
            subtitle: req.isEdit
                ? 'عدّل ما تشاء ثم احفظ — يستبدل السجل الأصلي'
                : 'كل خيارات الإدخال — تُحفظ فوراً',
            expanded: _expanded,
            onToggleExpand: () => setState(() => _expanded = !_expanded),
            onClose: _close,
          ),
          // المحتوى: النموذج الأفقي متعدد الأعمدة. تمريرةٌ رأسية احتياطية
          // تحمي عند الأوضاع القصيرة (مضغوط + أقسام مفتوحة) فلا يُقصّ شيء.
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: AddRecordScreen(
                // مفتاحٌ مقترنٌ بهوية الطلب: تبديل «جديد↔تعديل» أو سجلٍ لآخر
                // يعيد إنشاء حالة النموذج (تعبئة نظيفة) بلا تسرّب حقول.
                key: ValueKey(
                  'dock-${req.isEdit ? '${req.editKind}-${req.editEntry!['id']}' : 'new'}',
                ),
                compact: true,
                horizontal: true,
                editEntry: req.editEntry,
                editKind: req.editKind,
                editDebt: req.editDebt,
                onSaved: _close,
                onExpandedContent: _onExpandedContent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ترويسة اللوح الرفيعة — هوية زمردية (تدرّج العلامة): مقبض سحب + عنوان
/// + زر توسيع/طي + زر إغلاق (Esc).
class _DockHeader extends StatelessWidget {
  const _DockHeader({
    required this.title,
    required this.subtitle,
    required this.expanded,
    required this.onToggleExpand,
    required this.onClose,
  });

  final String title;
  final String subtitle;
  final bool expanded;
  final VoidCallback onToggleExpand;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 10, 8),
      decoration: const BoxDecoration(gradient: BrandColors.brandGradient),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // مقبض السحب العلوي — نقره يقلب التوسّع (توأم سحب اللوح).
          InkWell(
            key: const Key('dock-handle'),
            borderRadius: BorderRadius.circular(4),
            onTap: onToggleExpand,
            child: Container(
              width: 44,
              height: 5,
              margin: const EdgeInsets.only(bottom: 6, top: 2),
              decoration: BoxDecoration(
                color: BrandColors.goldLight.withValues(alpha: .55),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          Row(
            children: [
              const Icon(
                Icons.add_circle_rounded,
                size: 17,
                color: BrandColors.goldLight,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      key: const Key('dock-title'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: BrandColors.goldLight,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .72),
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
              // زر توسيع/طي.
              Tooltip(
                message: expanded ? 'طي اللوح' : 'توسيع اللوح',
                child: InkWell(
                  key: const Key('dock-expand'),
                  customBorder: const CircleBorder(),
                  onTap: onToggleExpand,
                  child: Container(
                    width: 32,
                    height: 32,
                    margin: const EdgeInsets.only(left: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .08),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color.fromRGBO(201, 162, 75, .2),
                      ),
                    ),
                    child: Icon(
                      expanded
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.keyboard_arrow_up_rounded,
                      size: 20,
                      color: BrandColors.goldLight,
                    ),
                  ),
                ),
              ),
              // زر الإغلاق (Esc).
              Tooltip(
                message: 'إغلاق (Esc)',
                child: InkWell(
                  key: const Key('dock-close'),
                  customBorder: const CircleBorder(),
                  onTap: onClose,
                  child: Container(
                    width: 32,
                    height: 32,
                    margin: const EdgeInsets.only(left: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .08),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color.fromRGBO(201, 162, 75, .2),
                      ),
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: BrandColors.goldLight,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
