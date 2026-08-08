/// ============================================================================
///  م100 — عرضُ رمز السن: خليّة Palmer (مطابِقة لمرجع Vue) أو نصّ FDI
/// ============================================================================
///
///  مطابقةُ `.palmer-cell` في مرجع Vue حرفياً (main.css):
///    display:inline-flex; توسيط; tabular-nums; font-weight:800;
///    font-size:15px; padding:3px 7px; direction:ltr; line-height:1.2;
///  والحدود حسب الربع (2px بلون النص = رمز Zsigmondy–Palmer):
///    q-ur: أسفل+يمين · q-ul: أسفل+يسار · q-lr: أعلى+يمين · q-ll: أعلى+يسار
///
///  FDI: نصٌّ عاديٌّ (رقمان) بلا إطار.
///
///  حجمُ الخط قابلٌ للتحجيم بـ[scale] للسياقات الصغيرة (بطاقة المريض)
///  مع الحفاظ على النِّسَب والتوازن البصري.
library;

import 'package:flutter/material.dart';

import 'tooth_notation.dart';
import 'tooth_summary.dart' show ToothCrossModel;

class ToothLabelView extends StatelessWidget {
  const ToothLabelView(
    this.label, {
    super.key,
    required this.color,
    this.scale = 1.0,
  });

  final ToothLabel label;
  final Color color;

  /// معاملُ تحجيمٍ (1.0 = مقاس Vue الأصلي 15px).
  final double scale;

  static const _brand700 = Color(0xFF114A38); // --brand-700 (افتراض اللون)

  @override
  Widget build(BuildContext context) {
    final c = color;
    final txt = Text(
      label.text,
      textDirection: TextDirection.ltr,
      style: TextStyle(
        fontSize: 15 * scale,
        height: 1.2,
        fontWeight: FontWeight.w800,
        color: c,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    if (!label.palmerBorder) {
      // FDI — نصٌّ فقط بنفس الحشو للتوازن مع خليّة Palmer.
      return Padding(
        padding: EdgeInsets.symmetric(
            horizontal: 7 * scale, vertical: 3 * scale),
        child: txt,
      );
    }
    // Palmer — إطارٌ ربعيٌّ حرفيٌّ.
    final side = BorderSide(color: c, width: 2 * scale);
    final q = label.quadrant;
    final bottom = q == 'UR' || q == 'UL';
    final top = q == 'LR' || q == 'LL';
    final right = q == 'UR' || q == 'LR';
    final left = q == 'UL' || q == 'LL';
    return Container(
      padding:
          EdgeInsets.symmetric(horizontal: 7 * scale, vertical: 3 * scale),
      decoration: BoxDecoration(
        border: Border(
          top: top ? side : BorderSide.none,
          bottom: bottom ? side : BorderSide.none,
          left: left ? side : BorderSide.none,
          right: right ? side : BorderSide.none,
        ),
      ),
      child: txt,
    );
  }

  /// بانٍ مريح من عنصر تخزينٍ `{q,n,d?}`.
  static ToothLabelView fromTooth(
    Map tooth, {
    required NotationSystem system,
    required Color color,
    double scale = 1.0,
    Key? key,
  }) =>
      ToothLabelView(
        toothLabelFromTooth(tooth, system: system),
        color: color,
        scale: scale,
        key: key,
      );

  /// لونُ العلامة الافتراضي (brand-700) حين لا يُمرَّر لون.
  static Color get defaultColor => _brand700;
}

/// م105 — شبكة Palmer الصليبية المصغّرة (بطاقة الملف): الخط الأفقي بين
/// الفكين والخط الوسطي العمودي، وأقسامها بنصوص [ToothCrossModel]
/// (يمين المريض على يسار الشاشة — العرف السريري نفسه، كصور المالك).
/// فكٌّ واحد ⇒ نصفها فقط: العمودي يخترق سطرَه الموجود ولا يمتد للغائب.
class ToothCrossView extends StatelessWidget {
  const ToothCrossView(
    this.model, {
    super.key,
    required this.quadrantColor,
    this.lineColor,
    this.scale = 1.0,
  });

  final ToothCrossModel model;

  /// لون نص كل ربع (UR/UL/LR/LL) — لوحة الأرباع الحالية نفسها.
  final Color Function(String quadrant) quadrantColor;

  /// لون الخطوط (الافتراض: لون العلامة الصامت).
  final Color? lineColor;

  final double scale;

  @override
  Widget build(BuildContext context) {
    final lc = (lineColor ?? ToothLabelView.defaultColor)
        .withValues(alpha: .65);
    final side = BorderSide(color: lc, width: 1.6 * scale);

    Widget cell(String text, String q, {required bool alignEnd}) =>
        Padding(
          padding: EdgeInsets.symmetric(
              horizontal: 3.5 * scale, vertical: 1.5 * scale),
          child: Align(
            widthFactor: 1,
            heightFactor: 1,
            alignment:
                alignEnd ? Alignment.centerRight : Alignment.centerLeft,
            child: Text(
              text,
              textDirection: TextDirection.ltr,
              style: TextStyle(
                fontSize: 10 * scale,
                height: 1.15,
                fontWeight: FontWeight.w800,
                color: quadrantColor(q),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        );

    // جدول 2×(1|2) بحدود داخلية: verticalInside = الخط الوسطي (يخترق
    // الصفوف الموجودة فقط)، وhorizontalInside = الخط الأفقي بين الفكين؛
    // وعند فكٍّ واحد يصير الخط الأفقي حداً خارجياً (أسفل العلوي/أعلى
    // السفلي) — هندسة صور المالك حرفياً بلا أي تمدد لانهائي.
    final both = model.hasUpper && model.hasLower;
    return Table(
      defaultColumnWidth: const IntrinsicColumnWidth(),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      textDirection: TextDirection.ltr,
      border: TableBorder(
        verticalInside: side,
        horizontalInside: both ? side : BorderSide.none,
        bottom: model.hasUpper && !model.hasLower
            ? side
            : BorderSide.none,
        top: model.hasLower && !model.hasUpper ? side : BorderSide.none,
      ),
      children: [
        if (model.hasUpper)
          TableRow(children: [
            cell(model.upperRight, 'UR', alignEnd: true),
            cell(model.upperLeft, 'UL', alignEnd: false),
          ]),
        if (model.hasLower)
          TableRow(children: [
            cell(model.lowerRight, 'LR', alignEnd: true),
            cell(model.lowerLeft, 'LL', alignEnd: false),
          ]),
      ],
    );
  }
}
