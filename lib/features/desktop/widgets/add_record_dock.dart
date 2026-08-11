/// ============================================================================
///  لوح «زيارة جديدة» الجانبي — Desktop Side Panel (م146 — عقد التصميم «د»)
/// ============================================================================
///
///  (قرار المالك — 2026‑08‑08): بديل اللوح السفلي المرسى (عقد «ج») بلوحٍ
///  **جانبيٍّ عائمٍ ينزلق من اليمين** فوق مساحة العمل بظلٍّ بلا حاجزٍ معتم —
///  الجدول يبقى مرئياً، والشريط الجانبي (يمين RTL) يبقى متاحاً. يوافق نمط
///  Material 3 القياسي للألواح الجانبية المرفوعة فوق المحتوى (8dp+).
///
///  لماذا استُبدل عقد «ج»: اللوح السفلي كان يقفز بين ارتفاعين (34%/62%)
///  عند فتح التركيبات/الدين، وأعمدته الأربعة متفاوتة الامتلاء، والحاسبة
///  زرٌّ ضخمٌ بعيدٌ عن حقل القيمة. اللوح الجانبي ثابت الإطار: التوسعات
///  تتحرك داخله بنعومة (AnimatedSize في النموذج) بلا تغيير في أبعاده.
///
///  البنية:
///  - [addRecordDockProvider] — حالة الفتح: null مغلق، وإلا
///    [AddRecordDockRequest] (الاسمان باقيان من عقد «ج» عمداً — كل مواضع
///    الاستدعاء والاختصارات تبقى كما هي حرفياً).
///  - [AddRecordSidePanel] — السطح العائم: عرضٌ ثابت (~660، ينكمش على
///    الشاشات الضيقة كي يبقى الجدول مرئياً)، ارتفاعٌ كامل لمساحة العمل،
///    ترويسةٌ زمردية رفيعة (عنوان + تلميح Esc + إغلاق)، والنموذج الكامل
///    [AddRecordScreen] بتخطيطه المقسّم الجديد داخل تمريرةِ طوارئ لا تعمل
///    إلا على الشاشات الأقصر من ميزانية اللاتمرير.
///  - انزلاقُ دخولٍ من حافة البداية (يمين RTL) عبر AnimatedSlide.
///
///  الحقول والمنطق والحفظ كلها في [AddRecordScreen] بلا تغيير — هذا الملف
///  غلافٌ بصري بحت (استضافة + انتقال + ترويسة).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/theme/app_theme.dart';
import '../../records/add_record_screen.dart' show AddRecordScreen;

/// طلب فتح اللوح: التعديل يحمل السجل الأصلي ونوعه ودينه؛ الجديد كلها null.
/// كائنٌ ثابت بسيط — تبديل المرجع كافٍ لإعادة بناء الشِل.
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

/// حالة لوح «زيارة جديدة» في نسخة الكمبيوتر — null = مغلق.
/// يضبطه [openAddRecordSheet] (فرع الديسكتوب) و_newVisit/Ctrl+N، ويعيده
/// Esc/زر الإغلاق/الحفظ الناجح إلى null.
final addRecordDockProvider = StateProvider<AddRecordDockRequest?>(
  (ref) => null,
);

/// م167/ج — موضع اللوح المسحوب (إحداثيات مساحة العمل). null = المرسى
/// الافتراضي (بداية RTL). يضبطه سحبُ الرأس ويُحفظ في تفضيلات الجهاز.
final addRecordDockPosProvider = StateProvider<Offset?>((ref) => null);

/// عرض اللوح — دالة مشتركة (اللوح نفسه وصدفة سطح المكتب للقص الذكي).
double addRecordPanelWidth(Size screen) =>
    (screen.width * .52).clamp(640.0, 840.0);

/// اللوح الجانبي العائم — يُبنى فقط حين [addRecordDockProvider] غير null.
class AddRecordSidePanel extends ConsumerStatefulWidget {
  const AddRecordSidePanel({
    super.key,
    required this.request,
    this.onDrag,
    this.onDragEnd,
  });

  final AddRecordDockRequest request;

  /// م167/ج — سحب اللوح من رأسه (تمرران من صدفة سطح المكتب).
  final void Function(Offset delta)? onDrag;
  final VoidCallback? onDragEnd;

  @override
  ConsumerState<AddRecordSidePanel> createState() => _AddRecordSidePanelState();
}

class _AddRecordSidePanelState extends ConsumerState<AddRecordSidePanel> {
  /// يقود انزلاق الدخول: يبدأ خارج الحافة ثم ينزلق للداخل بعد أول إطار.
  bool _in = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _in = true);
    });
  }

  void _close() => ref.read(addRecordDockProvider.notifier).state = null;

  @override
  Widget build(BuildContext context) {
    final req = widget.request;
    final screen = MediaQuery.sizeOf(context);
    // عرضٌ مريح لصفوف الحقول الثنائية؛ ينكمش على الشاشات الضيقة كي يبقى
    // جزءٌ من مساحة العمل مرئياً دائماً.
    // م167/ب — لوح أعرض بهوامش أرحب (طلب المالك: استغلال الشاشة بلا تلاصق).
    final width = addRecordPanelWidth(screen);
    // سقفُ ارتفاعٍ تعانق البطاقة المحتوى دونه: صافي مساحة العمل (تقديرٌ
    // متحفّظ ‎128 للهيدر/الشريط/الهوامش) — التمرير يعمل فوق هذا السقف فقط.
    final maxH = (screen.height - 128).clamp(360.0, 1000.0);

    return AnimatedSlide(
      // في RTL: Offset(-1,0) خارج حافة البداية (اليمين) — فينزلق منها.
      offset: _in ? Offset.zero : const Offset(-1, 0),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      // م146/و (قرار المالك «معانقة متحركة»): بطاقةٌ عائمة تعانق محتواها —
      // لا شريط بارتفاعٍ كامل ولا فراغٌ ميت أسفله. التوسعات تنمي قاعها
      // بانتقالٍ ناعمٍ واحد (AnimatedSize)، وConstrainedBox يسقُف الارتفاع
      // بصافي مساحة العمل فيعمل التمرير فوق ذلك السقف فقط.
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: Container(
            width: width,
            decoration: const BoxDecoration(
              // ظلٌّ نحو مساحة العمل — بطاقةٌ مرفوعة فوق المحتوى بلا حاجز.
              boxShadow: [
                BoxShadow(
                  color: Color.fromRGBO(10, 48, 36, .22),
                  blurRadius: 24,
                  spreadRadius: 2,
                  offset: Offset(-8, 4),
                ),
              ],
            ),
            child: Material(
              color: BrandColors.surface,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: BrandColors.gold.withValues(alpha: .30),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _PanelHeader(
                    onDrag: widget.onDrag,
                    onDragEnd: widget.onDragEnd,
                    title: req.isEdit ? 'تعديل السجل' : 'زيارة جديدة',
                    subtitle: req.isEdit
                        ? 'عدّل ما تشاء ثم احفظ — يستبدل السجل الأصلي'
                        : 'كل خيارات الإدخال — تُحفظ فوراً',
                    onClose: _close,
                  ),
                  // المحتوى يعانَق بارتفاعه الطبيعي؛ Flexible يسمح بالتمرير
                  // فقط حين يبلغ المحتوى سقف ConstrainedBox أعلاه.
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
                      child: AddRecordScreen(
                        // مفتاحٌ مقترن بهوية الطلب: تبديل «جديد↔تعديل» أو
                        // سجلٍ لآخر يعيد إنشاء حالة النموذج بلا تسرّب حقول.
                        key: ValueKey(
                          'panel-${req.isEdit ? '${req.editKind}-${req.editEntry!['id']}' : 'new'}',
                        ),
                        compact: true,
                        horizontal: true,
                        editEntry: req.editEntry,
                        editKind: req.editKind,
                        editDebt: req.editDebt,
                        onSaved: _close,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// الترويسة الزمردية الرفيعة — عنوانٌ وتلميح Esc وزرُّ إغلاق. لا أوضاع
/// ارتفاعٍ بعد اليوم: اللوح ثابت الإطار والتوسعات داخلية ناعمة.
class _PanelHeader extends StatelessWidget {
  const _PanelHeader({
    required this.title,
    required this.subtitle,
    required this.onClose,
    this.onDrag,
    this.onDragEnd,
  });

  final String title;
  final String subtitle;
  final VoidCallback onClose;

  /// م167/ج — سحب اللوح بالإمساك بالرأس.
  final void Function(Offset delta)? onDrag;
  final VoidCallback? onDragEnd;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: onDrag == null
          ? MouseCursor.defer
          : SystemMouseCursors.grab,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: onDrag == null ? null : (d) => onDrag!(d.delta),
        onPanEnd: onDragEnd == null ? null : (_) => onDragEnd!(),
        child: Container(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 9, 8, 9),
      decoration: const BoxDecoration(gradient: BrandColors.brandGradient),
      child: Row(
        children: [
          // م167/ج — مقبض السحب: أيقونة تدل على قابلية النقل.
          Icon(
            Icons.drag_indicator_rounded,
            size: 16,
            color: Colors.white.withValues(alpha: .55),
          ),
          const SizedBox(width: 4),
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
          // تلميح الاختصار — Esc يغلق (معالجته في DesktopShell).
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: const Color.fromRGBO(201, 162, 75, .25),
              ),
            ),
            child: Text(
              'Esc',
              style: TextStyle(
                color: Colors.white.withValues(alpha: .75),
                fontSize: 10,
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
                margin: const EdgeInsetsDirectional.only(start: 6),
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
        ),
      ),
    );
  }
}
