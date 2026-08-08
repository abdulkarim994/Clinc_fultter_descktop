/// أيقونات شريط التبويبات — نقل **حرفي** لملفات SVG الأصلية
/// (components/icons: IconHome/IconClinics/IconFinance/IconLabs/
/// IconCalendar): viewBox 24×24، stroke 1.7، رؤوس ووصلات مستديرة،
/// fill:none — مرسومة برسّامات مخصصة بنفس المسارات.
library;

import 'package:flutter/material.dart';

/// أيقونة تبويب مخططة بحجم [size] ولون [color].
class TabIcon extends StatelessWidget {
  const TabIcon(this.id, {super.key, this.size = 28, required this.color});

  final String id;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(size),
        painter: _TabIconPainter(id, color),
      );
}

class _TabIconPainter extends CustomPainter {
  const _TabIconPainter(this.id, this.color);

  final String id;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 24; // viewBox 24 → الحجم الفعلي.
    canvas.scale(k);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = color;

    switch (id) {
      case 'home':
        // M3 9l9-7 9 7v11a2 2 0 01-2 2H5a2 2 0 01-2-2z
        final p = Path()
          ..moveTo(3, 9)
          ..relativeLineTo(9, -7)
          ..relativeLineTo(9, 7)
          ..relativeLineTo(0, 11)
          ..relativeArcToPoint(const Offset(-2, 2),
              radius: const Radius.circular(2))
          ..lineTo(5, 22)
          ..relativeArcToPoint(const Offset(-2, -2),
              radius: const Radius.circular(2))
          ..close();
        canvas.drawPath(p, stroke);
        // polyline 9 22 9 12 15 12 15 22
        final door = Path()
          ..moveTo(9, 22)
          ..lineTo(9, 12)
          ..lineTo(15, 12)
          ..lineTo(15, 22);
        canvas.drawPath(door, stroke);
      case 'clinics':
        // M3 21h18  M5 21V7l7-4 7 4v14
        canvas.drawLine(const Offset(3, 21), const Offset(21, 21), stroke);
        final b = Path()
          ..moveTo(5, 21)
          ..lineTo(5, 7)
          ..relativeLineTo(7, -4)
          ..relativeLineTo(7, 4)
          ..lineTo(19, 21);
        canvas.drawPath(b, stroke);
        // M9 21V11h6v10
        final inner = Path()
          ..moveTo(9, 21)
          ..lineTo(9, 11)
          ..lineTo(15, 11)
          ..lineTo(15, 21);
        canvas.drawPath(inner, stroke);
        // M12 7v0 — نقطة صغيرة (رأس مستدير).
        canvas.drawLine(const Offset(12, 7), const Offset(12, 7.01), stroke);
      case 'finance':
        // rect x2 y5 w20 h14 rx3 + M2 10h20 + circle 12,15 r2
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                const Rect.fromLTWH(2, 5, 20, 14), const Radius.circular(3)),
            stroke);
        canvas.drawLine(const Offset(2, 10), const Offset(22, 10), stroke);
        canvas.drawCircle(const Offset(12, 15), 2, stroke);
      case 'labs':
        // السن: M7.5 3C5.6 3 4 4.6 4 6.9c0 1.6.4 2.9.9 4.4.4 1.1.6 2.1.8
        // 3.5.2 1.6.3 3.3 1.2 4.3.5.5 1.2.4 1.5-.2.5-.9.6-2.3.8-3.6.2-1.1
        // .3-2.1 1.3-2.1s1.1 1 1.3 2.1c.2 1.3.3 2.7.8 3.6.3.6 1 .7 1.5.2
        // .9-1 1-2.7 1.2-4.3.2-1.4.4-2.4.8-3.5.5-1.5.9-2.8.9-4.4
        // C20 4.6 18.4 3 16.5 3c-1.7 0-2.7 1-4.5 1S9.2 3 7.5 3Z
        final tooth = Path()
          ..moveTo(7.5, 3)
          ..cubicTo(5.6, 3, 4, 4.6, 4, 6.9)
          ..relativeCubicTo(0, 1.6, .4, 2.9, .9, 4.4)
          ..relativeCubicTo(.4, 1.1, .6, 2.1, .8, 3.5)
          ..relativeCubicTo(.2, 1.6, .3, 3.3, 1.2, 4.3)
          ..relativeCubicTo(.5, .5, 1.2, .4, 1.5, -.2)
          ..relativeCubicTo(.5, -.9, .6, -2.3, .8, -3.6)
          ..relativeCubicTo(.2, -1.1, .3, -2.1, 1.3, -2.1)
          // s1.1 1 1.3 2.1 — انعكاس نقطة الضبط للسلاسة (s command).
          ..relativeCubicTo(1.0, 0, 1.1, 1.0, 1.3, 2.1)
          ..relativeCubicTo(.2, 1.3, .3, 2.7, .8, 3.6)
          ..relativeCubicTo(.3, .6, 1.0, .7, 1.5, .2)
          ..relativeCubicTo(.9, -1.0, 1.0, -2.7, 1.2, -4.3)
          ..relativeCubicTo(.2, -1.4, .4, -2.4, .8, -3.5)
          ..relativeCubicTo(.5, -1.5, .9, -2.8, .9, -4.4)
          ..cubicTo(20, 4.6, 18.4, 3, 16.5, 3)
          ..relativeCubicTo(-1.7, 0, -2.7, 1, -4.5, 1)
          // S9.2 3 7.5 3 — انعكاس (يمر عبر 9.2,3).
          ..cubicTo(10.2, 4, 9.2, 3, 7.5, 3)
          ..close();
        canvas.drawPath(tooth, stroke);
        // البريق: M19 3.1l.5 1.45 1.45.5-1.45.5L19 7.5l-.5-1.45
        // L17.05 5.55 18.5 5.05z — ممتلئ بلا حد.
        final spark = Path()
          ..moveTo(19, 3.1)
          ..relativeLineTo(.5, 1.45)
          ..relativeLineTo(1.45, .5)
          ..relativeLineTo(-1.45, .5)
          ..lineTo(19, 7.5)
          ..relativeLineTo(-.5, -1.45)
          ..lineTo(17.05, 5.55)
          ..lineTo(18.5, 5.05)
          ..close();
        canvas.drawPath(spark, fill);
      case 'calendar':
        // rect x3 y4 w18 h18 rx3 + M16 2v4 M8 2v4 M3 10h18
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                const Rect.fromLTWH(3, 4, 18, 18), const Radius.circular(3)),
            stroke);
        canvas.drawLine(const Offset(16, 2), const Offset(16, 6), stroke);
        canvas.drawLine(const Offset(8, 2), const Offset(8, 6), stroke);
        canvas.drawLine(const Offset(3, 10), const Offset(21, 10), stroke);
        // نقطتا الأيام: circle 8,16 r1 + circle 12,16 r1 (ممتلئتان).
        canvas.drawCircle(const Offset(8, 16), 1, fill);
        canvas.drawCircle(const Offset(12, 16), 1, fill);
      case 'extra':
        // «إضافي» — دائرة بعلامة زائد داخلها (نفس أسلوب الخطوط المخططة
        // المستديرة): circle 12,12 r9 + خطّا الزائد الأفقي والعمودي.
        canvas.drawCircle(const Offset(12, 12), 9, stroke);
        canvas.drawLine(const Offset(12, 8), const Offset(12, 16), stroke);
        canvas.drawLine(const Offset(8, 12), const Offset(16, 12), stroke);
      default:
        canvas.drawCircle(const Offset(12, 12), 8, stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _TabIconPainter old) =>
      old.id != id || old.color != color;
}
