/// م174 — شاشة المقارنة «قبل/بعد» بقالب احترافي (قرار المالك): لوحتان
/// متساويتان بعنوانَي «قبل» و«بعد»، تحت كل صورة **ختم تاريخها الحقيقي**
/// بشريحة ذهبية، بترويسة اسم المركز واسم المريض وتذييل توقيعٍ أنيق —
/// كله بهوية التطبيق (أخضر داكن بحواف ذهبية).
///
/// التصدير: القالب يُلتقط صورة PNG عالية الدقة (RepaintBoundary ×3):
///   • حفظ لمعرض الهاتف (gal — هاتف فقط).
///   • مشاركة (واتساب وغيره — share_plus).
///   • طباعة PDF بنفس القالب (بنية الطباعة القائمة printOrSharePdf).
/// وزر تبديل «قبل/بعد» إن رغب المالك بعكس الترتيب التلقائي (الأقدم قبل).
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart' show dbDirProvider;
import '../../core/theme/app_theme.dart';
import '../desktop/desktop_gate.dart' show isDesktopUi;
import '../print/print_service.dart' show printOrSharePdf;

/// طرف مقارنة: بايتات الصورة + اسمها + تاريخها المنسق + طابعها الخام.
class XrayCompareEntry {
  const XrayCompareEntry({
    required this.bytes,
    required this.name,
    required this.date,
    required this.ts,
  });

  final Uint8List bytes;
  final String name;
  final String date;
  final int ts;
}

class XrayCompareScreen extends ConsumerStatefulWidget {
  const XrayCompareScreen({
    super.key,
    required this.before,
    required this.after,
    this.patientName = '',
    this.centerName = '',
  });

  final XrayCompareEntry before;
  final XrayCompareEntry after;
  final String patientName;
  final String centerName;

  @override
  ConsumerState<XrayCompareScreen> createState() =>
      _XrayCompareScreenState();
}

class _XrayCompareScreenState extends ConsumerState<XrayCompareScreen> {
  final _boundaryKey = GlobalKey();

  /// م174 — تبديل قبل/بعد (الترتيب التلقائي: الأقدم قبل).
  bool _swapped = false;
  bool _busy = false;

  XrayCompareEntry get _before => _swapped ? widget.after : widget.before;
  XrayCompareEntry get _after => _swapped ? widget.before : widget.after;

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          duration: const Duration(milliseconds: 1400),
          content: Text(msg)));

  /// التقاط القالب صورة PNG عالية الدقة (×3).
  Future<Uint8List?> _capture() async {
    final ro = _boundaryKey.currentContext?.findRenderObject();
    if (ro is! RenderRepaintBoundary) return null;
    final img = await ro.toImage(pixelRatio: 3);
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
          text:
              '${widget.centerName} — مقارنة قبل/بعد${widget.patientName.isEmpty ? '' : ' • ${widget.patientName}'}',
        );
      });

  Future<void> _printPdf() => _run((png) async {
        final doc = pw.Document();
        final img = pw.MemoryImage(png);
        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            build: (ctx) => pw.Center(
              child: pw.Image(img, fit: pw.BoxFit.contain),
            ),
          ),
        );
        final msg = await printOrSharePdf(ref.read(dbDirProvider),
            await doc.save(), 'xray_before_after.pdf');
        _snack(msg);
      });

  /// لوحة طرفٍ واحد: عنوان قبل/بعد + الصورة + ختم التاريخ.
  Widget _panel(XrayCompareEntry e, String label, Color chip) {
    return Expanded(
      child: Column(
        children: [
          // شارة قبل/بعد.
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: chip,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: Colors.white)),
          ),
          const SizedBox(height: 8),
          // الصورة — إطار ذهبي رقيق على خلفية سوداء (contain بلا تشويه).
          AspectRatio(
            aspectRatio: 3 / 4,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: BrandColors.gold.withValues(alpha: .55),
                    width: 1.4),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.memory(e.bytes,
                  fit: BoxFit.contain, gaplessPlayback: true),
            ),
          ),
          const SizedBox(height: 8),
          // ختم التاريخ تحت الصورة (قرار المالك).
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: BrandColors.gold.withValues(alpha: .16),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: BrandColors.gold.withValues(alpha: .5)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.calendar_today_rounded,
                  size: 11, color: BrandColors.gold),
              const SizedBox(width: 5),
              Text(
                e.date.isEmpty ? 'بلا تاريخ' : e.date,
                style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: BrandColors.gold),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final desktop = isDesktopUi(context);
    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('مقارنة قبل / بعد',
            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w900)),
        actions: [
          IconButton(
            key: const Key('xc-swap'),
            tooltip: 'تبديل قبل/بعد',
            icon: const Icon(Icons.swap_horiz_rounded),
            onPressed: () => setState(() => _swapped = !_swapped),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
        children: [
          // ══ القالب الاحترافي (يُلتقط كما يظهر حرفياً) ══
          RepaintBoundary(
            key: _boundaryKey,
            child: Container(
              key: const Key('xc-template'),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [Color(0xFF0F3528), Color(0xFF0A2A1F)],
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                    color: BrandColors.gold.withValues(alpha: .6),
                    width: 1.6),
              ),
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
              child: Column(
                children: [
                  // ── الترويسة: المركز + المريض ──
                  Text(
                    widget.centerName.isEmpty
                        ? 'مقارنة قبل / بعد'
                        : widget.centerName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: BrandColors.gold),
                  ),
                  if (widget.patientName.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      widget.patientName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Container(
                    width: 90,
                    height: 2,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        BrandColors.gold.withValues(alpha: 0),
                        BrandColors.gold,
                        BrandColors.gold.withValues(alpha: 0),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // ── اللوحتان: قبل (يمين) وبعد (يسار) ──
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _panel(_before, 'قبل', const Color(0xFF9A6A18)),
                      const SizedBox(width: 10),
                      _panel(_after, 'بعد', BrandColors.brand600),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // ── التذييل: توقيع المركز ──
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.health_and_safety_rounded,
                          size: 13,
                          color: BrandColors.gold.withValues(alpha: .8)),
                      const SizedBox(width: 5),
                      Text(
                        widget.centerName.isEmpty
                            ? 'عيادة الأسنان'
                            : widget.centerName,
                        style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white.withValues(alpha: .65)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // ══ أزرار التصدير ══
          Row(children: [
            if (!desktop) ...[
              Expanded(
                child: FilledButton.icon(
                  key: const Key('xc-save'),
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
                            fontSize: 12.5, fontWeight: FontWeight.w900)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: FilledButton.icon(
                key: const Key('xc-share'),
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
                key: const Key('xc-pdf'),
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
    );
  }
}
