/// مخطط الأسنان التفاعلي — نقل renderSVG من ToothReport.vue إلى CustomPaint:
/// نفس إحداثيات TOOTH_DATA الاثنتين والثلاثين حرفياً (الفك العلوي ry=107−h
/// والسفلي ry=113 على لوحة 320×215)، الخطان المتقطعان والقوسان والعناوين،
/// وحالات السن الثلاث: عادي/محدد/مُعالَج (ضمن معالجة مضافة). كشف النقر يتم
/// بنفس مستطيلات الرسم بعد تحويل إحداثيات اللمس إلى فضاء اللوحة المنطقي.
///
/// م100/7 — الطقم اللبني: هندسة ثانية بعشرين سناً (خمسة لكل ربع A–E) على
/// اللوحة والأقواس نفسها، بنِسَبٍ مشتقة من مخطط البالغ: قوسٌ أقصر (تشريحياً
/// صحيح) وأرحاءُ D/E أعرض. مفتاح السن اللبني `q:n:P` (لاحقة إضافية بحتة)،
/// ورمزُ الخلية يتبع نظام العرض المختار (Palmer/FDI) عبر [toothLabel].
library;

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';

import 'tooth_notation.dart';

/// [ربع، رقم، x، عرض، ارتفاع] — حرفياً من ToothReport.vue.
const toothData = <(String, int, double, double, double)>[
  ('UR', 1, 144, 14, 34), ('UR', 2, 129, 13, 30), ('UR', 3, 113, 14, 37),
  ('UR', 4, 96, 15, 28), ('UR', 5, 79, 15, 28), ('UR', 6, 57, 20, 25),
  ('UR', 7, 35, 20, 25), ('UR', 8, 16, 17, 22),
  ('UL', 1, 162, 14, 34), ('UL', 2, 178, 13, 30), ('UL', 3, 193, 14, 37),
  ('UL', 4, 209, 15, 28), ('UL', 5, 226, 15, 28), ('UL', 6, 243, 20, 25),
  ('UL', 7, 265, 20, 25), ('UL', 8, 287, 17, 22),
  ('LR', 1, 144, 14, 34), ('LR', 2, 129, 13, 30), ('LR', 3, 113, 14, 37),
  ('LR', 4, 96, 15, 28), ('LR', 5, 79, 15, 28), ('LR', 6, 57, 20, 25),
  ('LR', 7, 35, 20, 25), ('LR', 8, 16, 17, 22),
  ('LL', 1, 162, 14, 34), ('LL', 2, 178, 13, 30), ('LL', 3, 193, 14, 37),
  ('LL', 4, 209, 15, 28), ('LL', 5, 226, 15, 28), ('LL', 6, 243, 20, 25),
  ('LL', 7, 265, 20, 25), ('LL', 8, 287, 17, 22),
];

/// م100/7 — الطقم اللبني: A(قاطع مركزي) B(جانبي) C(ناب) D/E(رحى) لكل ربع.
/// نفس معادلة الرسم (العلوي ry=107−h والسفلي ry=113) وفجوة 2 بين الخلايا
/// والخط المتوسط؛ x الأيسر مرآةُ الأيمن حول منتصف اللوحة (x' = 320−x−w).
const primaryToothData = <(String, int, double, double, double)>[
  ('UR', 1, 141, 17, 32), ('UR', 2, 122, 17, 29), ('UR', 3, 103, 17, 34),
  ('UR', 4, 80, 21, 27), ('UR', 5, 55, 23, 25),
  ('UL', 1, 162, 17, 32), ('UL', 2, 181, 17, 29), ('UL', 3, 200, 17, 34),
  ('UL', 4, 219, 21, 27), ('UL', 5, 242, 23, 25),
  ('LR', 1, 141, 17, 32), ('LR', 2, 122, 17, 29), ('LR', 3, 103, 17, 34),
  ('LR', 4, 80, 21, 27), ('LR', 5, 55, 23, 25),
  ('LL', 1, 162, 17, 32), ('LL', 2, 181, 17, 29), ('LL', 3, 200, 17, 34),
  ('LL', 4, 219, 21, 27), ('LL', 5, 242, 23, 25),
];

const chartLogicalSize = Size(320, 215);

bool _isUpper(String q) => q == 'UR' || q == 'UL';

/// بيانات الهندسة حسب الطقم.
List<(String, int, double, double, double)> toothDataFor(Dentition d) =>
    d == Dentition.primary ? primaryToothData : toothData;

/// مستطيل السن في فضاء اللوحة المنطقي — نفس معادلة renderSVG.
/// المعامل [dentition] إضافي (الافتراض دائم — كل الاستدعاءات القائمة كما هي).
Rect toothRect(String q, int tn, {Dentition dentition = Dentition.adult}) {
  final t =
      toothDataFor(dentition).firstWhere((e) => e.$1 == q && e.$2 == tn);
  final ry = _isUpper(q) ? 107 - t.$5 : 113.0;
  return Rect.fromLTWH(t.$3, ry, t.$4, t.$5);
}

/// مفتاح السن الواقع تحت نقطة منطقية، أو null. في الطقم اللبني يعود
/// المفتاح بلاحقته `:P` (فيتمايز عن أسنان الدائم في مجموعة الاختيار).
String? toothAt(Offset logical, {Dentition dentition = Dentition.adult}) {
  for (final t in toothDataFor(dentition)) {
    final ry = _isUpper(t.$1) ? 107 - t.$5 : 113.0;
    final r = Rect.fromLTWH(t.$3, ry, t.$4, t.$5).inflate(1.5);
    if (r.contains(logical)) {
      return toothKey(t.$1, t.$2, dentition: dentition);
    }
  }
  return null;
}

class ToothChart extends StatelessWidget {
  const ToothChart({
    super.key,
    required this.selected,
    this.done = const {},
    this.onToggle,
    // م100 — معاملان إضافيان بافتراضٍ يطابق السلوك التاريخي حرفياً
    // (طقم دائم + رقم Palmer الموضعي)، فكل الاستدعاءات القائمة كما هي.
    this.dentition = Dentition.adult,
    this.system = NotationSystem.palmer,
  });

  final Set<String> selected;
  final Set<String> done;
  final void Function(String key)? onToggle;

  /// الطقم المعروض حالياً (يبدّل الهندسة ومفاتيح النقر — لا البيانات).
  final Dentition dentition;

  /// نظام ترقيم الخلايا المعروض (Palmer/FDI) — عرضٌ فقط.
  final NotationSystem system;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: chartLogicalSize.width / chartLogicalSize.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = constraints.maxWidth / chartLogicalSize.width;
          return GestureDetector(
            key: const Key('tooth-chart'),
            behavior: HitTestBehavior.opaque,
            onTapUp: onToggle == null
                ? null
                : (d) {
                    final key = toothAt(d.localPosition / scale,
                        dentition: dentition);
                    if (key != null) onToggle!(key);
                  },
            child: CustomPaint(
              painter: _ToothChartPainter(
                selected: selected,
                done: done,
                dentition: dentition,
                system: system,
              ),
              size: Size.infinite,
            ),
          );
        },
      ),
    );
  }
}

class _ToothChartPainter extends CustomPainter {
  _ToothChartPainter({
    required this.selected,
    required this.done,
    required this.dentition,
    required this.system,
  });

  final Set<String> selected;
  final Set<String> done;
  final Dentition dentition;
  final NotationSystem system;

  // ألوان النسق الفاتح كما في renderSVG (light).
  static const _line = Color.fromRGBO(27, 94, 71, .25);
  static const _arc = Color.fromRGBO(27, 94, 71, .15);
  static const _label = Color.fromRGBO(30, 58, 138, .4);
  static const _sublabel = Color.fromRGBO(30, 58, 138, .3);

  void _dashedLine(Canvas c, Offset a, Offset b, Paint p) {
    const dash = 3.0, gap = 3.0;
    final total = (b - a).distance;
    final dir = (b - a) / total;
    var t = 0.0;
    while (t < total) {
      final end = (t + dash).clamp(0, total).toDouble();
      c.drawLine(a + dir * t, a + dir * end, p);
      t += dash + gap;
    }
  }

  void _text(Canvas c, String s, Offset baselineStart, double fontSize,
      Color color,
      {bool bold = false, bool centered = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          fontSize: fontSize,
          color: color,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
      textDirection: TextDirection.rtl,
    )..layout();
    // في SVG الإحداثي y هو خط القاعدة؛ نقارب بارتفاع النص.
    final dx = centered ? baselineStart.dx - tp.width / 2 : baselineStart.dx;
    tp.paint(c, Offset(dx, baselineStart.dy - tp.height * .8));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / chartLogicalSize.width;
    canvas.scale(scale);

    final linePaint = Paint()
      ..color = _line
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;
    _dashedLine(canvas, const Offset(160, 6), const Offset(160, 209), linePaint);
    _dashedLine(canvas, const Offset(8, 110), const Offset(312, 110), linePaint);

    final arcPaint = Paint()
      ..color = _arc
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    canvas.drawPath(
      Path()
        ..moveTo(16, 107)
        ..quadraticBezierTo(90, 68, 160, 65)
        ..quadraticBezierTo(230, 68, 304, 107),
      arcPaint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(16, 113)
        ..quadraticBezierTo(90, 152, 160, 155)
        ..quadraticBezierTo(230, 152, 304, 113),
      arcPaint,
    );

    _text(canvas, 'يمين', const Offset(10, 18), 8, _label, bold: true);
    _text(canvas, 'يسار', const Offset(282, 18), 8, _label, bold: true);
    _text(canvas, 'الفك العلوي', const Offset(52, 52), 7.5, _sublabel);
    _text(canvas, 'الفك السفلي', const Offset(52, 170), 7.5, _sublabel);

    for (final t in toothDataFor(dentition)) {
      final (q, tn, x, w, h) = t;
      final ry = _isUpper(q) ? 107 - h : 113.0;
      final key = toothKey(q, tn, dentition: dentition);
      final active = selected.contains(key);
      final isDone = done.contains(key);

      final fill = active
          ? const Color.fromRGBO(27, 94, 71, .52)
          : isDone
              ? const Color.fromRGBO(45, 212, 160, .25)
              : const Color.fromRGBO(241, 245, 249, .95);
      final stroke = active
          ? const Color.fromRGBO(96, 165, 250, .95)
          : isDone
              ? const Color.fromRGBO(45, 212, 160, .5)
              : const Color.fromRGBO(27, 94, 71, .35);
      final textFill = active
          ? const Color.fromRGBO(255, 255, 255, .98)
          : isDone
              ? const Color.fromRGBO(45, 212, 160, .9)
              : const Color.fromRGBO(30, 58, 138, .6);

      final rrect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, ry, w, h), const Radius.circular(3));
      canvas.drawRRect(rrect, Paint()..color = fill);
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = stroke
          ..strokeWidth = active ? 1.6 : 1
          ..style = PaintingStyle.stroke,
      );
      // م100 — رمز الخلية حسب نظام العرض: Palmer الموضع (دائم) أو حرف
      // A–E (لبني)، وFDI الرقمان. عرضٌ محض — البيانات {q,n} كما هي.
      final cellText =
          toothLabel(q, tn, system: system, dentition: dentition).text;
      _text(canvas, cellText, Offset(x + w / 2, ry + h / 2 + 3.5), 8,
          textFill,
          bold: active, centered: true);
    }
  }

  @override
  bool shouldRepaint(_ToothChartPainter old) =>
      !setEquals(old.selected, selected) ||
      !setEquals(old.done, done) ||
      old.dentition != dentition ||
      old.system != system;
}
