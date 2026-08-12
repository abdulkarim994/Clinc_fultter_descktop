/// م172 — شاشة الكاميرا الداخلية لتصوير الأشعة (قرار المالك): كاميرا
/// خاصة بالتطبيق — لا تفتح تطبيق الكاميرا الأساسي. معاينة حية بملء
/// الشاشة، زر التقاطٍ دائري بهوية التطبيق (توهج ذهبي على قاعدة داكنة)،
/// وكل التقاطة **تُحفظ فوراً** عبر [onCapture] (مسار رفع الأشعة نفسه:
/// ضغط/وسم/حصة/طابور) مع عدّاد لقطات — فيمكن التقاط عدة صور متتالية
/// ثم العودة. رفض إذن الكاميرا أو غيابها يعرض رسالةً أنيقة لا انهياراً.
library;

import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class XrayCameraScreen extends StatefulWidget {
  const XrayCameraScreen({
    super.key,
    required this.patientName,
    required this.onCapture,
  });

  /// اسم المريض — لعنوان الشاشة وتسمية اللقطات.
  final String patientName;

  /// يُستدعى بكل لقطة فور التقاطها (اسم ملف، بايتات JPEG) — الحفظ الفوري.
  final Future<void> Function(String name, Uint8List bytes) onCapture;

  @override
  State<XrayCameraScreen> createState() => _XrayCameraScreenState();
}

class _XrayCameraScreenState extends State<XrayCameraScreen> {
  CameraController? _controller;
  String? _error;
  bool _busy = false;
  int _shots = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        setState(() => _error = 'لا توجد كاميرا متاحة على هذا الجهاز');
        return;
      }
      // الخلفية أولاً (تصوير الأشعة/المستندات) وإلا أول المتاح.
      final back = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );
      final ctl = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await ctl.initialize();
      if (!mounted) {
        await ctl.dispose();
        return;
      }
      setState(() => _controller = ctl);
    } on CameraException catch (e) {
      setState(() => _error = e.code == 'CameraAccessDenied'
          ? 'رُفض إذن الكاميرا — امنح التطبيق الوصول للكاميرا من إعدادات النظام'
          : 'تعذر فتح الكاميرا (${e.code})');
    } catch (_) {
      setState(() => _error = 'تعذر فتح الكاميرا على هذا الجهاز');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  /// التقاطٌ وحفظٌ فوري — تبقى الشاشة مفتوحةً للقطاتٍ متتالية.
  Future<void> _capture() async {
    final ctl = _controller;
    if (ctl == null || _busy) return;
    setState(() => _busy = true);
    try {
      final file = await ctl.takePicture();
      final bytes = await file.readAsBytes();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      await widget.onCapture('camera_$stamp.jpg', bytes);
      if (!mounted) return;
      setState(() => _shots++);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(milliseconds: 900),
          content: Text('حُفظت اللقطة ✓ ($_shots)'),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر الالتقاط — حاول مجدداً')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctl = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('تصوير مباشر',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
            Text(
              widget.patientName,
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          if (_shots > 0)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 14),
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
                  child: Text('$_shots لقطة',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: BrandColors.gold)),
                ),
              ),
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
                        size: 42, color: Colors.white.withValues(alpha: .6)),
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
                  child: CircularProgressIndicator(color: Colors.white54))
              : Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    Positioned.fill(child: CameraPreview(ctl)),
                    // شريط الالتقاط السفلي — قاعدة داكنة شفافة بزرٍّ
                    // دائري أبيض بحلقةٍ ذهبية (هوية التطبيق).
                    Container(
                      padding: const EdgeInsets.only(top: 14, bottom: 26),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x00000000), Color(0xB3000000)],
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          GestureDetector(
                            key: const Key('xray-cam-shutter'),
                            onTap: _capture,
                            child: Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: BrandColors.gold, width: 3.5),
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
                                          padding: EdgeInsets.all(14),
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2.5),
                                        )
                                      : null,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}
