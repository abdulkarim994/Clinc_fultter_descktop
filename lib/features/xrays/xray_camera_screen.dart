/// م172 — شاشة الكاميرا الداخلية لتصوير الأشعة: كاميرا خاصة بالتطبيق —
/// لا تفتح تطبيق الكاميرا الأساسي.
///
/// م173 — إصلاحٌ وتطوير شامل (قرار المالك):
///   • المعاينة تملأ الشاشة كاملةً بنسبة أبعادٍ صحيحة (كانت شريطاً
///     علوياً مشوهاً) — قصٌّ ذكي cover بمقياس نسبتَي الشاشة والكاميرا.
///   • زر تبديل الكاميرا أمامية/خلفية، وزر فلاش (مصباح)، وتكبيرٌ بقرصة
///     الأصابع مع مؤشر النسبة، وتركيزٌ بلمس نقطة المعاينة.
///   • **الحفظ المؤقت**: اللقطات تُجمع داخل الجلسة بشريط مصغرات (حذفٌ
///     مباشر من الشريط)، وزر «تم» يفتح شاشة المراجعة [XrayReviewScreen]
///     لاختيار ما يُرفع — **المحدَّد فقط يُعاد للمستدعي** والباقي يُحذف.
///   • الرجوع بلقطات معلقة يسأل قبل التجاهل. رفض الإذن رسالةٌ أنيقة.
library;

import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'xray_review_screen.dart';

/// لقطة جلسة: (اسم الملف، بايتات JPEG).
typedef XrayShot = (String, Uint8List);

class XrayCameraScreen extends StatefulWidget {
  const XrayCameraScreen({super.key, required this.patientName});

  /// اسم المريض — لعنوان الشاشة وتسمية اللقطات.
  final String patientName;

  @override
  State<XrayCameraScreen> createState() => _XrayCameraScreenState();
}

class _XrayCameraScreenState extends State<XrayCameraScreen> {
  List<CameraDescription> _cams = const [];
  CameraController? _controller;
  int _camIdx = 0;
  String? _error;
  bool _busy = false;
  bool _torch = false;

  // م173 — حدود التكبير وقيمته الحالية (قرصة الأصابع).
  double _zoomMin = 1, _zoomMax = 1, _zoom = 1, _zoomBase = 1;

  /// م173 — لقطات الجلسة المؤقتة (لا رفع قبل المراجعة).
  final List<XrayShot> _session = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      _cams = await availableCameras();
      if (_cams.isEmpty) {
        setState(() => _error = 'لا توجد كاميرا متاحة على هذا الجهاز');
        return;
      }
      // الخلفية أولاً (تصوير الأشعة/المستندات) وإلا أول المتاح.
      final backIdx = _cams.indexWhere(
          (c) => c.lensDirection == CameraLensDirection.back);
      await _useCamera(backIdx < 0 ? 0 : backIdx);
    } on CameraException catch (e) {
      setState(() => _error = e.code == 'CameraAccessDenied'
          ? 'رُفض إذن الكاميرا — امنح التطبيق الوصول للكاميرا من إعدادات النظام'
          : 'تعذر فتح الكاميرا (${e.code})');
    } catch (_) {
      setState(() => _error = 'تعذر فتح الكاميرا على هذا الجهاز');
    }
  }

  /// م173 — تشغيل كاميرا الفهرس المعطى (تُستعمل للفتح وللتبديل).
  Future<void> _useCamera(int idx) async {
    final old = _controller;
    _controller = null;
    if (mounted) setState(() {});
    await old?.dispose();
    final ctl = CameraController(
      _cams[idx],
      ResolutionPreset.high,
      enableAudio: false,
    );
    try {
      await ctl.initialize();
      _zoomMin = await ctl.getMinZoomLevel();
      _zoomMax = await ctl.getMaxZoomLevel();
      _zoom = _zoom.clamp(_zoomMin, _zoomMax);
      // المصباح يعاد تطبيقه إن كان مفعلاً (الخلفية فقط عادةً).
      if (_torch) {
        try {
          await ctl.setFlashMode(FlashMode.torch);
        } catch (_) {
          _torch = false;
        }
      }
      if (!mounted) {
        await ctl.dispose();
        return;
      }
      setState(() {
        _camIdx = idx;
        _controller = ctl;
        _error = null;
      });
    } on CameraException catch (e) {
      await ctl.dispose();
      if (mounted) {
        setState(() => _error = e.code == 'CameraAccessDenied'
            ? 'رُفض إذن الكاميرا — امنح التطبيق الوصول للكاميرا من إعدادات النظام'
            : 'تعذر فتح الكاميرا (${e.code})');
      }
    }
  }

  /// م173 — تبديل الكاميرا أمامية/خلفية.
  Future<void> _flipCamera() async {
    if (_cams.length < 2 || _busy) return;
    _torch = false; // الأمامية غالباً بلا مصباح — تصفير آمن.
    await _useCamera((_camIdx + 1) % _cams.length);
  }

  /// م173 — تشغيل/إيقاف الفلاش (وضع المصباح المستمر للتصوير الطبي).
  Future<void> _toggleTorch() async {
    final ctl = _controller;
    if (ctl == null) return;
    try {
      await ctl.setFlashMode(_torch ? FlashMode.off : FlashMode.torch);
      setState(() => _torch = !_torch);
    } catch (_) {
      _snack('الفلاش غير متاح على هذه الكاميرا');
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          duration: const Duration(milliseconds: 900),
          content: Text(msg)));

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  /// التقاطٌ للجلسة المؤقتة — تبقى الشاشة مفتوحةً للقطاتٍ متتالية.
  Future<void> _capture() async {
    final ctl = _controller;
    if (ctl == null || _busy) return;
    setState(() => _busy = true);
    try {
      final file = await ctl.takePicture();
      final bytes = await file.readAsBytes();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      setState(() => _session.add(('camera_$stamp.jpg', bytes)));
    } catch (_) {
      if (mounted) _snack('تعذر الالتقاط — حاول مجدداً');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// م173 — «تم»: شاشة المراجعة؛ إن أكّد الاختيار تُعاد اللقطات المحددة
  /// للمستدعي (فيرفعها) — والرجوع من المراجعة يعود للتصوير بلا فقد.
  Future<void> _finishSession() async {
    if (_session.isEmpty) return;
    final picked = await Navigator.of(context).push<List<XrayShot>>(
      MaterialPageRoute(
        builder: (_) => XrayReviewScreen(
          patientName: widget.patientName,
          shots: List.of(_session),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    Navigator.of(context).pop(picked);
  }

  /// م173 — رجوعٌ ولقطات معلقة: تأكيد التجاهل قبل الخروج.
  Future<void> _confirmLeave() async {
    if (_session.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تجاهل اللقطات؟', style: TextStyle(fontSize: 15)),
        content: Text(
          'لديك ${_session.length} لقطة لم تُراجع — الخروج الآن يحذفها '
          'نهائياً. راجِعها بزر «تم» لاختيار ما يُرفع.',
          style: const TextStyle(fontSize: 12.5),
        ),
        actions: [
          TextButton(
            key: const Key('xray-cam-leave-stay'),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('متابعة التصوير'),
          ),
          TextButton(
            key: const Key('xray-cam-leave-ok'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تجاهل وخروج',
                style: TextStyle(color: BrandColors.red)),
          ),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.of(context).pop();
  }

  /// م173/ب — معاينة «cover» بملء الشاشة (إصلاح المالك: كانت تظهر
  /// صندوقاً صغيراً وسط الشاشة): النمط القياسي المضمون — أبعاد حساس
  /// الكاميرا الحقيقية previewSize (مقلوبةً عرضاً/ارتفاعاً في الوضع
  /// العمودي) داخل FittedBox بوضع cover، فتملأ الشاشة دائماً بقصٍّ
  /// صحيح مهما كانت نسبة الجهاز — بلا أي معادلات مقياس هشة.
  /// لواقط الإيماءات (زوم القرصة + تركيز اللمس) طبقةٌ بملء الشاشة
  /// بإحداثيات مطبّعة عليها (لا داخل التحويل — يفسد إحداثيات اللمس).
  Widget _coverPreview(CameraController ctl) {
    final ps = ctl.value.previewSize;
    final portrait =
        MediaQuery.orientationOf(context) == Orientation.portrait;
    // أبعاد الحساس تأتي أفقيةً دائماً — تُقلب في الوضع العمودي.
    final w = ps == null ? 9.0 : (portrait ? ps.height : ps.width);
    final h = ps == null ? 16.0 : (portrait ? ps.width : ps.height);
    return LayoutBuilder(
      builder: (context, box) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        // تكبير بقرصة الأصابع + تركيز بلمس النقطة (على كامل الشاشة).
        onScaleStart: (_) => _zoomBase = _zoom,
        onScaleUpdate: (d) async {
          final z = (_zoomBase * d.scale).clamp(_zoomMin, _zoomMax);
          if ((z - _zoom).abs() < .01) return;
          _zoom = z;
          try {
            await ctl.setZoomLevel(z);
          } catch (_) {}
          if (mounted) setState(() {});
        },
        onTapDown: (d) async {
          final p = Offset(
            (d.localPosition.dx / box.maxWidth).clamp(0, 1),
            (d.localPosition.dy / box.maxHeight).clamp(0, 1),
          );
          try {
            await ctl.setFocusPoint(p);
            await ctl.setExposurePoint(p);
          } catch (_) {}
        },
        child: ClipRect(
          child: SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: w,
                height: h,
                child: CameraPreview(ctl),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctl = _controller;
    final hasTwoCams = _cams.length >= 2;
    return PopScope(
      canPop: _session.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            key: const Key('xray-cam-back'),
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: _confirmLeave,
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('تصوير مباشر',
                  style:
                      TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              Text(
                widget.patientName,
                style: const TextStyle(fontSize: 11, color: Colors.white70),
              ),
            ],
          ),
          actions: [
            if (_session.isNotEmpty)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 6),
                child: Center(
                  child: Container(
                    key: const Key('xray-cam-counter'),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: BrandColors.gold.withValues(alpha: .2),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: BrandColors.gold.withValues(alpha: .5)),
                    ),
                    child: Text('${_session.length} لقطة',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: BrandColors.gold)),
                  ),
                ),
              ),
            // م173 — «تم»: مراجعة اللقطات واختيار ما يُرفع.
            if (_session.isNotEmpty)
              TextButton.icon(
                key: const Key('xray-cam-done'),
                onPressed: _finishSession,
                icon: const Icon(Icons.check_circle_rounded,
                    size: 18, color: BrandColors.gold),
                label: const Text('تم',
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                        color: BrandColors.gold)),
              ),
          ],
        ),
        body: _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.no_photography_rounded,
                          size: 42,
                          color: Colors.white.withValues(alpha: .6)),
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        key: const Key('xray-cam-error'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              )
            : ctl == null
                ? const Center(
                    child:
                        CircularProgressIndicator(color: Colors.white54))
                : Stack(
                    alignment: Alignment.bottomCenter,
                    children: [
                      // م173 — المعاينة بملء الشاشة (كانت شريطاً علوياً).
                      Positioned.fill(child: _coverPreview(ctl)),
                      // مؤشر التكبير — يظهر فقط بعد تجاوز 1x.
                      if (_zoom > _zoomMin + .05)
                        PositionedDirectional(
                          top: 10,
                          start: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${_zoom.toStringAsFixed(1)}x',
                              key: const Key('xray-cam-zoom'),
                              style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white),
                            ),
                          ),
                        ),
                      // ── الشريط السفلي: مصغرات الجلسة + صف الأزرار ──
                      Container(
                        padding: const EdgeInsets.only(top: 12, bottom: 22),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x00000000), Color(0xCC000000)],
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // م173 — شريط المصغرات: الأحدث أولاً، نقرة
                            // تكبّر، و«×» تحذف من الجلسة مباشرة.
                            if (_session.isNotEmpty)
                              SizedBox(
                                height: 62,
                                child: ListView.builder(
                                  key: const Key('xray-cam-strip'),
                                  scrollDirection: Axis.horizontal,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10),
                                  itemCount: _session.length,
                                  itemBuilder: (_, i) {
                                    final idx = _session.length - 1 - i;
                                    final shot = _session[idx];
                                    return Padding(
                                      padding:
                                          const EdgeInsetsDirectional.only(
                                              end: 6),
                                      child: Stack(children: [
                                        InkWell(
                                          key: Key('xray-cam-thumb-$idx'),
                                          onTap: () =>
                                              _previewShot(shot.$2),
                                          child: ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            child: Image.memory(
                                              shot.$2,
                                              width: 56,
                                              height: 56,
                                              fit: BoxFit.cover,
                                              gaplessPlayback: true,
                                            ),
                                          ),
                                        ),
                                        PositionedDirectional(
                                          top: 0,
                                          end: 0,
                                          child: InkWell(
                                            key: Key(
                                                'xray-cam-thumb-del-$idx'),
                                            onTap: () => setState(() =>
                                                _session.removeAt(idx)),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.all(2),
                                              decoration:
                                                  const BoxDecoration(
                                                color: Colors.black87,
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(
                                                  Icons.close_rounded,
                                                  size: 13,
                                                  color: Colors.white),
                                            ),
                                          ),
                                        ),
                                      ]),
                                    );
                                  },
                                ),
                              ),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // الفلاش (مصباح مستمر).
                                _RoundTool(
                                  key: const Key('xray-cam-flash'),
                                  icon: _torch
                                      ? Icons.flash_on_rounded
                                      : Icons.flash_off_rounded,
                                  active: _torch,
                                  onTap: _toggleTorch,
                                ),
                                const SizedBox(width: 26),
                                // زر الالتقاط الدائري بحلقة ذهبية.
                                GestureDetector(
                                  key: const Key('xray-cam-shutter'),
                                  onTap: _capture,
                                  child: Container(
                                    width: 72,
                                    height: 72,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: BrandColors.gold,
                                          width: 3.5),
                                      boxShadow: [
                                        BoxShadow(
                                          color: BrandColors.gold
                                              .withValues(alpha: .45),
                                          blurRadius: 16,
                                        ),
                                      ],
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(6),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: _busy
                                              ? Colors.white54
                                              : Colors.white,
                                        ),
                                        child: _busy
                                            ? const Padding(
                                                padding:
                                                    EdgeInsets.all(14),
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2.5),
                                              )
                                            : null,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 26),
                                // تبديل الكاميرا أمامية/خلفية.
                                _RoundTool(
                                  key: const Key('xray-cam-flip'),
                                  icon: Icons.cameraswitch_rounded,
                                  onTap: hasTwoCams ? _flipCamera : null,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  /// م173 — معاينة لقطةٍ مكبرة من شريط المصغرات (تقريبٌ بالقرصة).
  void _previewShot(Uint8List bytes) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.pop(ctx),
        child: InteractiveViewer(
          maxScale: 6,
          child: Center(child: Image.memory(bytes)),
        ),
      ),
    );
  }
}

/// زر أداةٍ دائري صغير على شريط الالتقاط (فلاش/تبديل) بهوية التطبيق.
class _RoundTool extends StatelessWidget {
  const _RoundTool(
      {super.key, required this.icon, this.onTap, this.active = false});

  final IconData icon;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active
              ? BrandColors.gold.withValues(alpha: .25)
              : Colors.white.withValues(alpha: .08),
          border: Border.all(
              color: active
                  ? BrandColors.gold
                  : Colors.white.withValues(alpha: enabled ? .35 : .15)),
        ),
        child: Icon(icon,
            size: 21,
            color: active
                ? BrandColors.gold
                : Colors.white.withValues(alpha: enabled ? .9 : .35)),
      ),
    );
  }
}
