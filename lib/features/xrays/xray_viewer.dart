/// عارض الأشعة — نقل جوهر XrayViewer.vue: ملء الشاشة بخلفية داكنة، تكبير
/// وتحريك (InteractiveViewer حتى ×5)، تدوير ربع لفة، عكس الألوان، سطوع
/// وتباين بمصفوفة ألوان (نفس دلالات مرشحات CSS: invert ثم brightness ثم
/// contrast)، تنقل سابق/تالي، وحذف بتأكيد. النسخة الكاملة من الملف المحلي
/// وإلا فالمصغرة (سلوك «الأوفلاين» نفسه).
///
/// م174 — (قرار المالك):
///   • تنقلٌ بأسهم لوحة المفاتيح على الكمبيوتر (يمين = السابق، يسار =
///     التالي — مطابقة أزرار الشاشة بالاتجاه العربي)، وبسحب الإصبع على
///     الهاتف — فقط حين لا تكبير كي لا يتعارض مع تحريك الصورة المكبرة.
///   • زر حفظ الصورة لمعرض الهاتف (هاتف فقط — أيقونة حفظ بالترويسة).
///   • ختم تاريخ الصورة سطراً صغيراً تحت العنوان.
///   • «مقارنة»: اختيار صورةٍ ثانية من ملف المريض ثم شاشة قالب «قبل/
///     بعد» الاحترافي [XrayCompareScreen] بختم تاريخٍ تحت كل صورة.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show KeyDownEvent, LogicalKeyboardKey;
import 'package:gal/gal.dart';

import '../../core/theme/app_theme.dart';
import '../desktop/desktop_gate.dart' show isDesktopUi;
import 'xray_compare_studio.dart';

class XrayViewerScreen extends StatefulWidget {
  const XrayViewerScreen({
    super.key,
    required this.keys_,
    required this.startIndex,
    required this.bytesOf,
    required this.nameOf,
    this.dateOf,
    this.tsOf,
    this.patientName = '',
    this.centerName = '',
    this.onDelete,
  });

  final List<String> keys_;
  final int startIndex;
  final Uint8List? Function(String key) bytesOf;
  final String Function(String key) nameOf;

  /// م174 — تاريخ الصورة المنسق (ختم العارض والمقارنة) — اختياري.
  final String Function(String key)? dateOf;

  /// م174 — طابع الإنشاء الخام لترتيب «قبل/بعد» تلقائياً — اختياري.
  final int Function(String key)? tsOf;

  /// م174 — لقالب المقارنة الاحترافي (ترويسة وتذييل).
  final String patientName;
  final String centerName;

  final void Function(String key)? onDelete;

  @override
  State<XrayViewerScreen> createState() => _XrayViewerScreenState();
}

class _XrayViewerScreenState extends State<XrayViewerScreen> {
  late int idx;
  int quarterTurns = 0;
  bool invert = false;
  double brightness = 100;
  double contrast = 100;
  final _tc = TransformationController();

  @override
  void initState() {
    super.initState();
    idx = widget.startIndex.clamp(0, widget.keys_.length - 1);
  }

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  void _reset() => setState(() {
        quarterTurns = 0;
        invert = false;
        brightness = 100;
        contrast = 100;
        _tc.value = Matrix4.identity();
      });

  void _go(int delta) => setState(() {
        idx = (idx + delta).clamp(0, widget.keys_.length - 1);
        _reset();
      });

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          duration: const Duration(milliseconds: 1200),
          content: Text(msg)));

  /// م174 — حفظ الصورة الحالية في معرض الهاتف (زر الترويسة).
  Future<void> _saveToPhone(String key, Uint8List bytes) async {
    try {
      final name = widget.nameOf(key).replaceAll(RegExp(r'[^\w؀-ۿ]+'), '_');
      await Gal.putImageBytes(bytes,
          name: 'xray_${name}_${DateTime.now().millisecondsSinceEpoch}');
      _snack('حُفظت الصورة في معرض الهاتف ✓');
    } catch (_) {
      _snack('تعذر الحفظ — تحقق من إذن الوصول للصور');
    }
  }

  /// م175 — زر «مقارنة» (قرار المالك): أولاً خيارُ العائلة — «قوالب صور
  /// الابتسامة» أو «قوالب صور الأشعة» — ثم اختيارٌ متعدد (2–6 صور)
  /// فاستوديو المقارنة بقوالب العائلة.
  void _openCompare(String currentKey) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF10192B),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (sheetCtx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(children: [
              Icon(Icons.compare_rounded,
                  size: 17, color: BrandColors.gold),
              SizedBox(width: 7),
              Expanded(
                child: Text('نوع المقارنة',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                        color: Colors.white)),
              ),
            ]),
          ),
          ListTile(
            key: const Key('xv-cmp-smile'),
            leading: const Icon(Icons.sentiment_very_satisfied_rounded,
                color: BrandColors.gold),
            title: const Text('قوالب صور الابتسامة',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Colors.white)),
            subtitle: const Text('مقاسات النشر على فيسبوك',
                style: TextStyle(fontSize: 11, color: Colors.white54)),
            onTap: () {
              Navigator.pop(sheetCtx);
              _pickImages(currentKey, 'smile');
            },
          ),
          ListTile(
            key: const Key('xv-cmp-xray'),
            leading: const Icon(Icons.broken_image_rounded,
                color: BrandColors.gold),
            title: const Text('قوالب صور الأشعة',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Colors.white)),
            subtitle: const Text('ثنائي وشريط تسلسل وشبكة',
                style: TextStyle(fontSize: 11, color: Colors.white54)),
            onTap: () {
              Navigator.pop(sheetCtx);
              _pickImages(currentKey, 'xray');
            },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  /// م175 — الاختيار المتعدد (2–6 صور، الحالية محددة سلفاً) ثم الاستوديو.
  void _pickImages(String currentKey, String family) {
    final picked = <String>{currentKey};
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF10192B),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Row(children: [
                const Icon(Icons.photo_library_rounded,
                    size: 17, color: BrandColors.gold),
                const SizedBox(width: 7),
                const Expanded(
                  child: Text('اختر الصور (2–6)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w900,
                          color: Colors.white)),
                ),
                Text('${picked.length}',
                    key: const Key('xv-pick-count'),
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                        color: BrandColors.gold)),
              ]),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final k in widget.keys_)
                    CheckboxListTile(
                      key: Key('xv-cmp-pick-$k'),
                      dense: true,
                      activeColor: BrandColors.gold,
                      checkColor: const Color(0xFF10192B),
                      controlAffinity: ListTileControlAffinity.leading,
                      value: picked.contains(k),
                      secondary: _sheetThumb(k),
                      title: Text(widget.nameOf(k),
                          style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.white)),
                      subtitle: widget.dateOf == null
                          ? null
                          : Text(widget.dateOf!(k),
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.white54)),
                      onChanged: (v) => setSheet(() {
                        if (v == true) {
                          if (picked.length >= 6) return;
                          picked.add(k);
                        } else if (picked.length > 1) {
                          picked.remove(k);
                        }
                      }),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('xv-cmp-go'),
                  style: FilledButton.styleFrom(
                    backgroundColor: picked.length >= 2
                        ? BrandColors.gold
                        : Colors.white24,
                    foregroundColor: picked.length >= 2
                        ? const Color(0xFF10192B)
                        : Colors.white54,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                  onPressed: picked.length < 2
                      ? null
                      : () {
                          Navigator.pop(sheetCtx);
                          _pushStudio(family, picked.toList());
                        },
                  icon: const Icon(Icons.auto_awesome_rounded, size: 17),
                  label: Text(
                    picked.length < 2
                        ? 'اختر صورة ثانية على الأقل'
                        : 'فتح الاستوديو (${picked.length} صور)',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _sheetThumb(String k) {
    final b = widget.bytesOf(k);
    if (b == null) {
      return const SizedBox(
          width: 44,
          height: 44,
          child: Icon(Icons.image_not_supported_outlined,
              color: Colors.white38));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child:
          Image.memory(b, width: 44, height: 44, fit: BoxFit.cover),
    );
  }

  /// م175 — فتح الاستوديو بالعناصر المختارة (يرتبها تصاعدياً بالتاريخ).
  void _pushStudio(String family, List<String> keys) {
    final items = <CompareItem>[];
    for (final k in keys) {
      final b = widget.bytesOf(k);
      if (b == null) {
        _snack('تعذر تحميل إحدى الصور');
        return;
      }
      items.add(CompareItem(
        bytes: b,
        name: widget.nameOf(k),
        date: widget.dateOf?.call(k) ?? '',
        ts: widget.tsOf?.call(k) ?? 0,
      ));
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CompareStudioScreen(
          family: family,
          items: items,
          patientName: widget.patientName,
          centerName: widget.centerName,
        ),
      ),
    );
  }

  /// مصفوفة invert→brightness→contrast المركّبة (دلالات مرشحات CSS).
  List<double> _matrix() {
    var a = invert ? -1.0 : 1.0;
    var o = invert ? 255.0 : 0.0;
    final b = brightness / 100;
    a *= b;
    o *= b;
    final c = contrast / 100;
    a *= c;
    o = o * c + 128 * (1 - c);
    return [
      a, 0, 0, 0, o, //
      0, a, 0, 0, o, //
      0, 0, a, 0, o, //
      0, 0, 0, 1, 0, //
    ];
  }

  @override
  Widget build(BuildContext context) {
    final key = widget.keys_.isEmpty ? null : widget.keys_[idx];
    final bytes = key == null ? null : widget.bytesOf(key);
    final date =
        key == null || widget.dateOf == null ? '' : widget.dateOf!(key);
    final desktop = isDesktopUi(context);

    return Scaffold(
      backgroundColor: const Color(0xF20B1220),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              key == null
                  ? ''
                  : '${widget.nameOf(key)} (${idx + 1}/${widget.keys_.length})',
              style: const TextStyle(fontSize: 14),
            ),
            // م174 — ختم تاريخ الصورة تحت العنوان.
            if (date.isNotEmpty)
              Text(date,
                  key: const Key('xv-date'),
                  style: const TextStyle(
                      fontSize: 10.5, color: Colors.white60)),
          ],
        ),
        actions: [
          // م174 — «مقارنة قبل/بعد» (صورتان فأكثر بالملف).
          if (key != null && widget.keys_.length >= 2)
            IconButton(
              key: const Key('xv-compare'),
              tooltip: 'مقارنة قبل/بعد',
              icon: const Icon(Icons.compare_rounded),
              onPressed: () => _openCompare(key),
            ),
          // م174 — حفظ للهاتف (هاتف فقط).
          if (key != null && bytes != null && !desktop)
            IconButton(
              key: const Key('xv-save'),
              tooltip: 'حفظ إلى الهاتف',
              icon: const Icon(Icons.save_alt_rounded),
              onPressed: () => _saveToPhone(key, bytes),
            ),
          if (widget.onDelete != null && key != null)
            IconButton(
              key: const Key('xv-delete'),
              tooltip: 'حذف',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('حذف الصورة؟'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('إلغاء')),
                      FilledButton(
                          key: const Key('xv-delete-confirm'),
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('حذف')),
                    ],
                  ),
                );
                if (ok == true && mounted) {
                  widget.onDelete!(key);
                  Navigator.of(this.context).pop();
                }
              },
            ),
        ],
      ),
      // م174 — أسهم لوحة المفاتيح (كمبيوتر): يمين = السابق ويسار =
      // التالي — مطابقة اتجاه أزرار الشاشة العربية حرفياً.
      body: Focus(
        autofocus: true,
        onKeyEvent: (node, e) {
          if (e is! KeyDownEvent) return KeyEventResult.ignored;
          if (e.logicalKey == LogicalKeyboardKey.arrowRight) {
            if (idx > 0) _go(-1);
            return KeyEventResult.handled;
          }
          if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
            if (idx < widget.keys_.length - 1) _go(1);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Column(
          children: [
            Expanded(
              child: bytes == null
                  ? const Center(
                      child: Text('لا صورة',
                          style: TextStyle(color: Colors.white54)))
                  : InteractiveViewer(
                      transformationController: _tc,
                      minScale: 0.5,
                      maxScale: 5,
                      // م174 — سحب الإصبع (هاتف): قذفة أفقية حين لا
                      // تكبير تنقل بين الصور — والمكبرة تتحرك كالسابق.
                      onInteractionEnd: (d) {
                        final scale = _tc.value.getMaxScaleOnAxis();
                        if (scale > 1.05) return;
                        final vx = d.velocity.pixelsPerSecond.dx;
                        if (vx > 600 && idx > 0) {
                          _go(-1);
                        } else if (vx < -600 &&
                            idx < widget.keys_.length - 1) {
                          _go(1);
                        }
                      },
                      child: Center(
                        child: ColorFiltered(
                          colorFilter: ColorFilter.matrix(_matrix()),
                          child: RotatedBox(
                            quarterTurns: quarterTurns,
                            child:
                                Image.memory(bytes, gaplessPlayback: true),
                          ),
                        ),
                      ),
                    ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 2,
                  children: [
                    IconButton(
                      key: const Key('xv-prev'),
                      tooltip: 'السابق',
                      onPressed: idx > 0 ? () => _go(-1) : null,
                      icon: const Icon(Icons.chevron_right_rounded,
                          color: Colors.white70),
                    ),
                    IconButton(
                      key: const Key('xv-rotate'),
                      tooltip: 'تدوير',
                      onPressed: () => setState(
                          () => quarterTurns = (quarterTurns + 1) % 4),
                      icon: const Icon(Icons.rotate_90_degrees_cw_rounded,
                          color: Colors.white70),
                    ),
                    IconButton(
                      key: const Key('xv-invert'),
                      tooltip: 'عكس الألوان',
                      onPressed: () => setState(() => invert = !invert),
                      icon: Icon(Icons.invert_colors_rounded,
                          color: invert ? Colors.amber : Colors.white70),
                    ),
                    IconButton(
                      key: const Key('xv-bright-down'),
                      tooltip: 'سطوع −',
                      onPressed: () => setState(() =>
                          brightness = (brightness - 15).clamp(20, 300)),
                      icon: const Icon(Icons.brightness_low_rounded,
                          color: Colors.white70),
                    ),
                    IconButton(
                      key: const Key('xv-bright-up'),
                      tooltip: 'سطوع +',
                      onPressed: () => setState(() =>
                          brightness = (brightness + 15).clamp(20, 300)),
                      icon: const Icon(Icons.brightness_high_rounded,
                          color: Colors.white70),
                    ),
                    IconButton(
                      key: const Key('xv-contrast-up'),
                      tooltip: 'تباين +',
                      onPressed: () => setState(
                          () => contrast = (contrast + 15).clamp(20, 300)),
                      icon: const Icon(Icons.contrast_rounded,
                          color: Colors.white70),
                    ),
                    IconButton(
                      key: const Key('xv-reset'),
                      tooltip: 'إعادة ضبط',
                      onPressed: _reset,
                      icon: const Icon(Icons.refresh_rounded,
                          color: Colors.white70),
                    ),
                    IconButton(
                      key: const Key('xv-next'),
                      tooltip: 'التالي',
                      onPressed: idx < widget.keys_.length - 1
                          ? () => _go(1)
                          : null,
                      icon: const Icon(Icons.chevron_left_rounded,
                          color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
