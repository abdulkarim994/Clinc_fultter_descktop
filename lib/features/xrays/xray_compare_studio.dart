/// م175 — «استوديو المقارنة» (قرار المالك): يحل محل قالب م174 الثابت.
///
///   • قوالبُ بياناتٍ من [kCompareTemplates] بعائلتين (ابتسامة/أشعة) —
///     شريط اختيار قوالب أعلى اللوحة، واللوحة تُعاد صياغتها فوراً.
///   • **قصٌّ حي يقتل الحواف السوداء**: كل صورة داخل فتحتها بنمط cover
///     عبر InteractiveViewer — سحبٌ وقرصة بالهاتف، وسحب الفأرة وعجلتها
///     بالكمبيوتر، وأسهم لوحة المفاتيح (+/-) للفتحة المحددة بالنقر.
///   • 2–6 صور: ثنائي (قبل/بعد)، شريط أفقي، شبكة، عمودي مكدس — نصٌّ
///     تحريري تحت كل صورة (افتراضيه تاريخها الحقيقي).
///   • عنوان حر (افتراضيه اسم المريض — يُستبدل بأي جملة أو يُمحى)
///     وسطر ثانٍ اختياري + شريحة «مدة المتابعة» المحسوبة تلقائياً بين
///     أقدم وأحدث صورة (followUpSentence).
///   • شعار المركز (شعار الطباعة نفسه من الإعدادات) بزاوية تُختار من
///     أربع أو يُخفى، بلوحٍ فاتح/غامق يناسب كل القوالب.
///   • التصدير: PNG بدقة نشرٍ عالية (عرض ≥1080) حفظاً ومشاركةً وPDF.
library;

import 'dart:convert' show base64Decode;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart' show KeyDownEvent, LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart' show appConfigProvider, dbDirProvider;
import '../../core/theme/app_theme.dart';
import '../desktop/desktop_gate.dart' show isDesktopUi;
import '../print/print_service.dart' show printOrSharePdf;
import 'compare_templates.dart';

/// عنصر مقارنة: بايتات الصورة + اسمها + تاريخها المنسق + طابعها الخام.
class CompareItem {
  CompareItem({
    required this.bytes,
    required this.name,
    required this.date,
    required this.ts,
  }) : caption = date;

  final Uint8List bytes;
  final String name;
  final String date;
  final int ts;

  /// النص تحت الصورة — افتراضيه التاريخ، يحرره الطبيب.
  String caption;
}

class CompareStudioScreen extends ConsumerStatefulWidget {
  const CompareStudioScreen({
    super.key,
    required this.family,
    required this.items,
    this.patientName = '',
    this.centerName = '',
  });

  /// 'smile' أو 'xray' — من خيارَي زر المقارنة (قرار المالك).
  final String family;

  /// 2–6 عناصر مرتبة تصاعدياً بالتاريخ.
  final List<CompareItem> items;

  final String patientName;
  final String centerName;

  @override
  ConsumerState<CompareStudioScreen> createState() =>
      _CompareStudioScreenState();
}

class _CompareStudioScreenState extends ConsumerState<CompareStudioScreen> {
  final _boundaryKey = GlobalKey();
  late CompareTemplate _tpl;
  late final List<CompareItem> _items;
  late final List<TransformationController> _tcs;

  late final TextEditingController _titleCtl;
  final _subtitleCtl = TextEditingController();

  /// الفتحة المحددة (تمييز ذهبي) — هدف أسهم لوحة المفاتيح بالكمبيوتر.
  int _sel = 0;
  bool _swapped = false; // للثنائي: عكس قبل/بعد.
  bool _busy = false;

  // ── الشعار ──
  static const _corners = ['tr', 'tl', 'br', 'bl'];
  int _logoCorner = 0;
  bool _logoVisible = true;
  bool? _logoDarkPlate; // null = تلقائي حسب القالب.

  @override
  void initState() {
    super.initState();
    _tpl = templatesOf(widget.family).first;
    _items = List.of(widget.items)..sort((a, b) => a.ts.compareTo(b.ts));
    _tcs = [for (final _ in _items) TransformationController()];
    _titleCtl = TextEditingController(text: widget.patientName);
  }

  @override
  void dispose() {
    for (final c in _tcs) {
      c.dispose();
    }
    _titleCtl.dispose();
    _subtitleCtl.dispose();
    super.dispose();
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          duration: const Duration(milliseconds: 1400),
          content: Text(msg)));

  /// ترتيب العرض (الثنائي يقبل التبديل قبل/بعد).
  List<int> get _order {
    final idx = [for (var i = 0; i < _items.length; i++) i];
    if (_items.length == 2 && _swapped) return [idx[1], idx[0]];
    return idx;
  }

  /// شعار المركز من الإعدادات (شعار الطباعة نفسه) — null إن غاب أو SVG.
  Uint8List? get _logoBytes {
    final logo = '${ref.read(appConfigProvider)['logo'] ?? ''}';
    if (!logo.startsWith('data:') || logo.contains('svg')) return null;
    final i = logo.indexOf(',');
    if (i < 0) return null;
    try {
      return base64Decode(logo.substring(i + 1));
    } catch (_) {
      return null;
    }
  }

  /// مدة المتابعة المحسوبة بين أقدم وأحدث صورة.
  String get _followUp =>
      followUpSentence(_items.first.ts, _items.last.ts);

  // ═══════════ لوحة المفاتيح (كمبيوتر): تحريك الفتحة المحددة ═══════════

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final tc = _tcs[_sel];
    const step = 12.0;
    double dx = 0, dy = 0, scale = 1;
    if (e.logicalKey == LogicalKeyboardKey.arrowLeft) dx = step;
    if (e.logicalKey == LogicalKeyboardKey.arrowRight) dx = -step;
    if (e.logicalKey == LogicalKeyboardKey.arrowUp) dy = step;
    if (e.logicalKey == LogicalKeyboardKey.arrowDown) dy = -step;
    if (e.logicalKey == LogicalKeyboardKey.equal ||
        e.logicalKey == LogicalKeyboardKey.numpadAdd) {
      scale = 1.12;
    }
    if (e.logicalKey == LogicalKeyboardKey.minus ||
        e.logicalKey == LogicalKeyboardKey.numpadSubtract) {
      scale = 1 / 1.12;
    }
    if (dx == 0 && dy == 0 && scale == 1) return KeyEventResult.ignored;
    final m = tc.value.clone();
    if (scale != 1) {
      final s = m.getMaxScaleOnAxis() * scale;
      if (s < 1 || s > 5) return KeyEventResult.handled;
      m.scaleByDouble(scale, scale, scale, 1);
    } else {
      m.translateByDouble(dx / m.getMaxScaleOnAxis(),
          dy / m.getMaxScaleOnAxis(), 0, 1);
    }
    tc.value = m;
    setState(() {});
    return KeyEventResult.handled;
  }

  // ═══════════ التصدير ═══════════

  Future<Uint8List?> _capture() async {
    final ro = _boundaryKey.currentContext?.findRenderObject();
    if (ro is! RenderRepaintBoundary) return null;
    // دقة نشرٍ عالية: العرض النهائي ≥ 1080 بكسل.
    final w = ro.size.width;
    final ratio = (1080 / w).clamp(2.0, 4.0);
    final img = await ro.toImage(pixelRatio: ratio);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }

  Future<void> _run(Future<void> Function(Uint8List png) job) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final png = await _capture();
      if (png == null) {
        _snack('تعذر تجهيز الصورة');
        return;
      }
      await job(png);
    } catch (_) {
      _snack('تعذرت العملية — حاول مجدداً');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveToPhone() => _run((png) async {
        try {
          await Gal.putImageBytes(png,
              name:
                  'before_after_${DateTime.now().millisecondsSinceEpoch}');
          _snack('حُفظت صورة المقارنة في معرض الهاتف ✓');
        } catch (_) {
          _snack('تعذر الحفظ — تحقق من إذن الوصول للصور');
        }
      });

  Future<void> _share() => _run((png) async {
        await Share.shareXFiles(
          [
            XFile.fromData(png,
                mimeType: 'image/png', name: 'before_after.png'),
          ],
          text: '${widget.centerName} — مقارنة قبل/بعد',
        );
      });

  Future<void> _printPdf() => _run((png) async {
        final doc = pw.Document();
        final img = pw.MemoryImage(png);
        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            build: (ctx) =>
                pw.Center(child: pw.Image(img, fit: pw.BoxFit.contain)),
          ),
        );
        final msg = await printOrSharePdf(ref.read(dbDirProvider),
            await doc.save(), 'xray_before_after.pdf');
        _snack(msg);
      });

  // ═══════════ تحرير النصوص ═══════════

  Future<void> _editText(TextEditingController ctl, String label,
      {String? hint}) async {
    final tmp = TextEditingController(text: ctl.text);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(label, style: const TextStyle(fontSize: 14.5)),
        content: TextField(
          key: const Key('cs-edit-field'),
          controller: tmp,
          autofocus: true,
          maxLines: 2,
          decoration: InputDecoration(hintText: hint ?? ''),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
              key: const Key('cs-edit-ok'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حفظ')),
        ],
      ),
    );
    if (ok == true && mounted) {
      setState(() => ctl.text = tmp.text.trim());
    }
  }

  Future<void> _editCaption(int i) async {
    final tmp = TextEditingController(text: _items[i].caption);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('نص الصورة', style: TextStyle(fontSize: 14.5)),
        content: TextField(
          key: const Key('cs-edit-field'),
          controller: tmp,
          autofocus: true,
          decoration:
              const InputDecoration(hintText: 'التاريخ أو أي وصف...'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
              key: const Key('cs-edit-ok'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حفظ')),
        ],
      ),
    );
    if (ok == true && mounted) {
      setState(() => _items[i].caption = tmp.text.trim());
    }
  }

  // ═══════════ البناء ═══════════

  @override
  Widget build(BuildContext context) {
    final desktop = isDesktopUi(context);
    final tpls = templatesOf(widget.family);
    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(
          widget.family == 'smile'
              ? 'استوديو الابتسامة — قبل/بعد'
              : 'استوديو الأشعة — قبل/بعد',
          style:
              const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
        ),
        actions: [
          if (_items.length == 2)
            IconButton(
              key: const Key('cs-swap'),
              tooltip: 'تبديل قبل/بعد',
              icon: const Icon(Icons.swap_horiz_rounded),
              onPressed: () => setState(() => _swapped = !_swapped),
            ),
        ],
      ),
      body: Focus(
        autofocus: desktop,
        onKeyEvent: _onKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
          children: [
            // ── شريط القوالب ──
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final t in tpls)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 6),
                      child: _pill(
                        key: Key('cs-tpl-${t.id}'),
                        label: t.name,
                        active: _tpl.id == t.id,
                        onTap: () => setState(() => _tpl = t),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // ── اللوحة (تُلتقط كما تظهر حرفياً) ──
            RepaintBoundary(
              key: _boundaryKey,
              child: _canvas(),
            ),
            const SizedBox(height: 6),
            Text(
              desktop
                  ? 'اسحب بالفأرة وكبّر بعجلتها داخل أي صورة — والأسهم و +/− للفتحة المحددة'
                  : 'اسحب بإصبعك داخل أي صورة لضبط القص وقرّب بإصبعين — لا حواف سوداء',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10.5, color: BrandColors.mut2),
            ),
            const SizedBox(height: 10),
            // ── أدوات النص ──
            Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: [
                _pill(
                  key: const Key('cs-edit-title'),
                  icon: Icons.edit_rounded,
                  label: 'العنوان',
                  onTap: () => _editText(_titleCtl, 'عنوان اللوحة',
                      hint: 'اسم المريض أو أي جملة — فارغ = بلا عنوان'),
                ),
                _pill(
                  key: const Key('cs-edit-subtitle'),
                  icon: Icons.short_text_rounded,
                  label: 'سطر ثانٍ',
                  onTap: () => _editText(_subtitleCtl, 'السطر الثاني',
                      hint: 'وصف الحالة أو المعالجة...'),
                ),
                if (_followUp.isNotEmpty)
                  _pill(
                    key: const Key('cs-followup'),
                    icon: Icons.timelapse_rounded,
                    label: _followUp,
                    gold: true,
                    onTap: () =>
                        setState(() => _subtitleCtl.text = _followUp),
                  ),
                // ── الشعار ──
                _pill(
                  key: const Key('cs-logo-corner'),
                  icon: _logoVisible
                      ? Icons.branding_watermark_rounded
                      : Icons.visibility_off_rounded,
                  label: _logoVisible
                      ? 'الشعار: ${switch (_corners[_logoCorner]) {
                          'tr' => 'أعلى يمين',
                          'tl' => 'أعلى يسار',
                          'br' => 'أسفل يمين',
                          _ => 'أسفل يسار',
                        }}'
                      : 'الشعار: مخفي',
                  onTap: () => setState(() {
                    if (!_logoVisible) {
                      _logoVisible = true;
                      _logoCorner = 0;
                    } else if (_logoCorner < _corners.length - 1) {
                      _logoCorner++;
                    } else {
                      _logoVisible = false;
                    }
                  }),
                ),
                _pill(
                  key: const Key('cs-logo-plate'),
                  icon: Icons.contrast_rounded,
                  label:
                      'لوح الشعار: ${_logoDarkPlate == null ? 'تلقائي' : _logoDarkPlate! ? 'غامق' : 'فاتح'}',
                  onTap: () => setState(() {
                    _logoDarkPlate = switch (_logoDarkPlate) {
                      null => false,
                      false => true,
                      true => null,
                    };
                  }),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // ── أزرار التصدير ──
            Row(children: [
              if (!desktop) ...[
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('cs-save'),
                    style: FilledButton.styleFrom(
                      backgroundColor: BrandColors.gold,
                      foregroundColor: BrandColors.brand900,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                    ),
                    onPressed: _busy ? null : _saveToPhone,
                    icon: const Icon(Icons.save_alt_rounded, size: 17),
                    label: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('حفظ',
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w900)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: FilledButton.icon(
                  key: const Key('cs-share'),
                  style: FilledButton.styleFrom(
                    backgroundColor: BrandColors.brand600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                  onPressed: _busy ? null : _share,
                  icon: const Icon(Icons.share_rounded, size: 17),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('مشاركة',
                        style: TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w900)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('cs-pdf'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white38),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                  onPressed: _busy ? null : _printPdf,
                  icon: const Icon(Icons.print_rounded, size: 17),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('PDF',
                        style: TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w900)),
                  ),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  /// زر شريحةٍ مخصص (لا Chip — ماتيريال 3 يتجاهل ألوانه على الداكن).
  Widget _pill({
    required Key key,
    required String label,
    required VoidCallback onTap,
    IconData? icon,
    bool active = false,
    bool gold = false,
  }) {
    final bg = active
        ? BrandColors.gold
        : gold
            ? BrandColors.gold.withValues(alpha: .16)
            : Colors.white.withValues(alpha: .08);
    final fg = active
        ? BrandColors.brand900
        : gold
            ? BrandColors.gold
            : Colors.white.withValues(alpha: .88);
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
            color: active || gold
                ? BrandColors.gold.withValues(alpha: .7)
                : Colors.white24),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: key,
        onTap: onTap,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 5),
            ],
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 250),
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: fg)),
            ),
          ]),
        ),
      ),
    );
  }

  // ═══════════ اللوحة ═══════════

  Widget _canvas() {
    final title = _titleCtl.text.trim();
    final subtitle = _subtitleCtl.text.trim();
    return AspectRatio(
      aspectRatio: _tpl.aspect,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [_tpl.bgTop, _tpl.bgBottom],
          ),
          borderRadius: BorderRadius.circular(16),
          border:
              Border.all(color: _tpl.frame.withValues(alpha: .7), width: 1.4),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                children: [
                  // ── الترويسة: عنوان حر + سطر ثانٍ ──
                  if (title.isNotEmpty)
                    Text(title,
                        key: const Key('cs-title'),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: _tpl.titleColor)),
                  if (subtitle.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(subtitle,
                          key: const Key('cs-subtitle'),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: _tpl.textColor)),
                    ),
                  if (title.isNotEmpty || subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Container(
                      width: 80,
                      height: 1.6,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [
                          _tpl.frame.withValues(alpha: 0),
                          _tpl.frame,
                          _tpl.frame.withValues(alpha: 0),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  // ── الفتحات ──
                  Expanded(child: _slotsArea()),
                  const SizedBox(height: 6),
                  // ── التذييل: اسم المركز ──
                  Text(
                    widget.centerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: _tpl.textColor.withValues(alpha: .75)),
                  ),
                ],
              ),
            ),
            // ── الشعار بالزاوية المختارة ──
            if (_logoVisible && _logoBytes != null) _logoOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _logoOverlay() {
    final corner = _corners[_logoCorner];
    final dark = _logoDarkPlate ?? _tpl.lightOnDark;
    final plate = Container(
      key: const Key('cs-logo'),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: dark
            ? Colors.black.withValues(alpha: .55)
            : Colors.white.withValues(alpha: .88),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _tpl.frame.withValues(alpha: .5)),
      ),
      child: Image.memory(_logoBytes!,
          width: 34, height: 34, fit: BoxFit.contain),
    );
    return PositionedDirectional(
      top: corner == 'tr' || corner == 'tl' ? 8 : null,
      bottom: corner == 'br' || corner == 'bl' ? 8 : null,
      start: corner == 'tr' || corner == 'br' ? 8 : null,
      end: corner == 'tl' || corner == 'bl' ? 8 : null,
      child: plate,
    );
  }

  /// توزيع الفتحات حسب نمط القالب وعدد الصور — الأنماط الثنائية تتحول
  /// شبكةً/شريطاً تلقائياً مع 3+ صور (سلوكٌ رشيق لا خطأ).
  Widget _slotsArea() {
    final order = _order;
    final n = order.length;
    var layout = _tpl.layout;
    if (n > 2 && (layout == SlotLayout.duo || layout == SlotLayout.stacked)) {
      layout = widget.family == 'xray' ? SlotLayout.row : SlotLayout.grid;
    }
    switch (layout) {
      case SlotLayout.duo:
        return Row(children: [
          Expanded(child: _slot(order[0], label: 'قبل')),
          const SizedBox(width: 8),
          Expanded(child: _slot(order[1], label: 'بعد')),
        ]);
      case SlotLayout.stacked:
        return Column(children: [
          Expanded(child: _slot(order[0], label: 'قبل')),
          const SizedBox(height: 8),
          Expanded(child: _slot(order[1], label: 'بعد')),
        ]);
      case SlotLayout.row:
        return Row(children: [
          for (var i = 0; i < n; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(child: _slot(order[i])),
          ],
        ]);
      case SlotLayout.grid:
        final cols = (n / 2).ceil();
        final top = order.take(cols).toList();
        final bottom = order.skip(cols).toList();
        Widget rowOf(List<int> xs) => Expanded(
              child: Row(children: [
                for (var i = 0; i < xs.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(child: _slot(xs[i])),
                ],
                // موازنة الصف الناقص (5 صور): فراغ بعرض فتحة.
                for (var i = xs.length; i < cols; i++) ...[
                  const SizedBox(width: 6),
                  const Expanded(child: SizedBox()),
                ],
              ]),
            );
        return Column(
            children: [rowOf(top), const SizedBox(height: 6), rowOf(bottom)]);
    }
  }

  /// فتحة واحدة: شارة قبل/بعد (للثنائي) + القص الحي + النص التحريري.
  Widget _slot(int i, {String? label}) {
    final it = _items[i];
    final selected = _sel == i;
    return Column(children: [
      if (label != null) ...[
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 2.5),
          decoration: BoxDecoration(
            color: label == 'قبل' ? _tpl.beforeChip : _tpl.afterChip,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(label,
              style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                  color: Colors.white)),
        ),
        const SizedBox(height: 5),
      ],
      // ── القص الحي (لا حواف سوداء): cover عند 1x وقصٌّ متحرك ──
      Expanded(
        child: GestureDetector(
          key: Key('cs-slot-$i'),
          onTapDown: (_) {
            if (_sel != i) setState(() => _sel = i);
          },
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected
                    ? BrandColors.gold
                    : _tpl.frame.withValues(alpha: .55),
                width: selected ? 2 : 1.2,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: InteractiveViewer(
                transformationController: _tcs[i],
                minScale: 1,
                maxScale: 5,
                child: SizedBox.expand(
                  child: Image.memory(it.bytes,
                      fit: BoxFit.cover, gaplessPlayback: true),
                ),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 4),
      // ── النص التحريري تحت الصورة (افتراضيه التاريخ) ──
      InkWell(
        key: Key('cs-caption-$i'),
        borderRadius: BorderRadius.circular(10),
        onTap: () => _editCaption(i),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 9, vertical: 2.5),
          decoration: BoxDecoration(
            color: _tpl.stampBg,
            borderRadius: BorderRadius.circular(10),
            border:
                Border.all(color: _tpl.frame.withValues(alpha: .45)),
          ),
          child: Text(
            it.caption.isEmpty ? '—' : it.caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                color: _tpl.stampText),
          ),
        ),
      ),
    ]);
  }
}
