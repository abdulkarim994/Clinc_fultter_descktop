/// عارض الأشعة — نقل جوهر XrayViewer.vue: ملء الشاشة بخلفية داكنة، تكبير
/// وتحريك (InteractiveViewer حتى ×5)، تدوير ربع لفة، عكس الألوان، سطوع
/// وتباين بمصفوفة ألوان (نفس دلالات مرشحات CSS: invert ثم brightness ثم
/// contrast)، تنقل سابق/تالي، وحذف بتأكيد. النسخة الكاملة من الملف المحلي
/// وإلا فالمصغرة (سلوك «الأوفلاين» نفسه).
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

class XrayViewerScreen extends StatefulWidget {
  const XrayViewerScreen({
    super.key,
    required this.keys_,
    required this.startIndex,
    required this.bytesOf,
    required this.nameOf,
    this.onDelete,
  });

  final List<String> keys_;
  final int startIndex;
  final Uint8List? Function(String key) bytesOf;
  final String Function(String key) nameOf;
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

    return Scaffold(
      backgroundColor: const Color(0xF20B1220),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(
          key == null ? '' : '${widget.nameOf(key)} (${idx + 1}/${widget.keys_.length})',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
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
      body: Column(
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
                    child: Center(
                      child: ColorFiltered(
                        colorFilter: ColorFilter.matrix(_matrix()),
                        child: RotatedBox(
                          quarterTurns: quarterTurns,
                          child: Image.memory(bytes, gaplessPlayback: true),
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
                    onPressed: () =>
                        setState(() => quarterTurns = (quarterTurns + 1) % 4),
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
                    onPressed: () =>
                        setState(() => contrast = (contrast + 15).clamp(20, 300)),
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
                    onPressed:
                        idx < widget.keys_.length - 1 ? () => _go(1) : null,
                    icon: const Icon(Icons.chevron_left_rounded,
                        color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
