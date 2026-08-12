/// م173 — شاشة مراجعة لقطات الكاميرا الداخلية (قرار المالك): بعد جلسة
/// التصوير تُعرض اللقطات شبكةً — الكل محددٌ افتراضياً، نقرة تبدل تحديد
/// اللقطة، وضغطة مطولة (أو زر العين) تكبّرها بملء الشاشة قبل القرار.
/// زر «رفع المحدد (n)» يعيد **المحدَّد فقط** للمستدعي والباقي يُحذف
/// نهائياً — مع زر تحديد/إلغاء تحديد الكل. الرجوع يعود للتصوير بلا فقد.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class XrayReviewScreen extends StatefulWidget {
  const XrayReviewScreen(
      {super.key, required this.patientName, required this.shots});

  final String patientName;

  /// لقطات الجلسة: (اسم الملف، بايتات JPEG).
  final List<(String, Uint8List)> shots;

  @override
  State<XrayReviewScreen> createState() => _XrayReviewScreenState();
}

class _XrayReviewScreenState extends State<XrayReviewScreen> {
  /// المحدد للرفع — الكل افتراضياً (قرار المالك: أختار ما يُرفع).
  late final Set<int> _picked =
      {for (var i = 0; i < widget.shots.length; i++) i};

  bool get _allPicked => _picked.length == widget.shots.length;

  void _toggleAll() => setState(() {
        if (_allPicked) {
          _picked.clear();
        } else {
          _picked.addAll([for (var i = 0; i < widget.shots.length; i++) i]);
        }
      });

  /// تكبير لقطةٍ بملء الشاشة (تقريبٌ بالقرصة) قبل القرار.
  void _zoomShot(int i) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.pop(ctx),
        child: InteractiveViewer(
          maxScale: 6,
          child: Center(
              child: Image.memory(widget.shots[i].$2,
                  key: Key('xray-rev-zoomed-$i'))),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final n = _picked.length;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('مراجعة اللقطات',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
            Text(widget.patientName,
                style: const TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
        actions: [
          TextButton.icon(
            key: const Key('xray-rev-all'),
            onPressed: _toggleAll,
            icon: Icon(
              _allPicked
                  ? Icons.remove_done_rounded
                  : Icons.done_all_rounded,
              size: 18,
              color: BrandColors.gold,
            ),
            label: Text(_allPicked ? 'إلغاء الكل' : 'تحديد الكل',
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: BrandColors.gold)),
          ),
        ],
      ),
      body: GridView.builder(
        key: const Key('xray-rev-grid'),
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 90),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemCount: widget.shots.length,
        itemBuilder: (_, i) {
          final on = _picked.contains(i);
          return GestureDetector(
            key: Key('xray-rev-item-$i'),
            onTap: () => setState(
                () => on ? _picked.remove(i) : _picked.add(i)),
            onLongPress: () => _zoomShot(i),
            child: Stack(fit: StackFit.expand, children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.memory(widget.shots[i].$2,
                    fit: BoxFit.cover, gaplessPlayback: true),
              ),
              // إطار التحديد + تعتيم غير المحدد (سيُحذف).
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: on
                          ? BrandColors.gold
                          : Colors.white.withValues(alpha: .18),
                      width: on ? 2.5 : 1),
                  color: on
                      ? Colors.transparent
                      : Colors.black.withValues(alpha: .55),
                ),
              ),
              PositionedDirectional(
                top: 5,
                start: 5,
                child: Icon(
                  on
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 21,
                  color: on
                      ? BrandColors.gold
                      : Colors.white.withValues(alpha: .55),
                ),
              ),
              // زر عين صغير للتكبير (إضافةً للضغطة المطولة).
              PositionedDirectional(
                bottom: 5,
                end: 5,
                child: InkWell(
                  key: Key('xray-rev-eye-$i'),
                  onTap: () => _zoomShot(i),
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: Colors.black87,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.zoom_in_rounded,
                        size: 15, color: Colors.white),
                  ),
                ),
              ),
            ]),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
          child: Row(children: [
            Expanded(
              child: FilledButton.icon(
                key: const Key('xray-rev-ok'),
                style: FilledButton.styleFrom(
                  backgroundColor:
                      n == 0 ? Colors.white24 : BrandColors.gold,
                  foregroundColor:
                      n == 0 ? Colors.white54 : BrandColors.brand900,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: n == 0
                    ? null
                    : () => Navigator.of(context).pop([
                          for (var i = 0; i < widget.shots.length; i++)
                            if (_picked.contains(i)) widget.shots[i],
                        ]),
                icon: const Icon(Icons.cloud_upload_rounded, size: 18),
                label: Text(
                  n == 0
                      ? 'لا لقطات محددة'
                      : 'رفع المحدد ($n) — الباقي يُحذف',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w900),
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              key: const Key('xray-rev-back'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: Colors.white38),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 12),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('رجوع للتصوير',
                  style:
                      TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
            ),
          ]),
        ),
      ),
    );
  }
}
