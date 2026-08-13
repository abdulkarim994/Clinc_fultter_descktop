/// م178 — جداول الأرباح المشتركة بين المنصتين (بهوية جداول الخزينة م154):
///
/// • [ProfitsClinicsTable] — جدول أرباح العيادات المنظم (العيادة/الإيراد/
///   ربح الطبيب/ربح العيادة) بدل البطاقات — شهرياً أو سنوياً.
/// • [ProfitsGrandTable] — جدول «الإجمالي العام»: صف الإجمالي، ثم صف
///   «المصروفات» بقيمته **تحت عمود ربح العيادة** فيقرأ الطرح عمودياً،
///   ثم صف «صافي ربح العيادة» المميز (طلب المالك — سهولة الحساب).
/// • [YearPnlTable] — جدول الأرباح والخسائر السنوي: 12 شهراً ×
///   (الإيراد/الطبيب/العيادة/المصروفات/الصافي) + صف إجمالي السنة.
/// • [YearKpiCards] — مؤشرات السنة (إيراد/طبيب/عيادة/مصروفات/صافي/هامش)
///   مع نسبة التغير عن السنة السابقة (YoY) — شبكة هاتفياً وشريط كمبيوترياً.
///
/// كل الخلايا الرقمية بأرقام جدولية (tabularFigures) وداخل FittedBox
/// انكماشي — فلا فيضان مع خط Ahem العريض في الاختبارات (درس القسم 11).
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../print/treatment_tables.dart' show formatNumber;
import 'profits_logic.dart';

/// نص ترويسة عمود — توأم ترويسات جداول الخزينة.
TextStyle _headStyle() => TextStyle(
    fontSize: 11, fontWeight: FontWeight.w800, color: BrandColors.mut2);

/// خلية رقمية: أرقام جدولية داخل FittedBox انكماشي (أمان Ahem).
Widget _numCell(String txt,
        {Color? color, bool bold = false, double fs = 12.5, Key? key}) =>
    Expanded(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(txt,
            key: key,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: fs,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w700,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()])),
      ),
    );

Widget _headCell(String txt) => Expanded(
    child: Text(txt, textAlign: TextAlign.center, style: _headStyle()));

/// م178 — جدول أرباح العيادات (شهرياً أو سنوياً حسب [title]).
class ProfitsClinicsTable extends StatelessWidget {
  const ProfitsClinicsTable({
    super.key,
    required this.title,
    required this.rows,
    this.dense = false,
  });

  final String title;
  final List<ClinicProfitRow> rows;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final n = formatNumber;
    final fs = dense ? 12.0 : 12.5;
    return Card(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Text(title,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: BrandColors.brandText)),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(children: [
                Expanded(
                    flex: 2,
                    child: Text('العيادة', style: _headStyle())),
                _headCell('الإيراد'),
                _headCell('ربح الطبيب'),
                _headCell('ربح العيادة'),
              ]),
            ),
            const SizedBox(height: 4),
            Divider(height: 1, color: BrandColors.line),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.all(18),
                child: Center(
                  child: Text('لا توجد بيانات',
                      style:
                          TextStyle(fontSize: 12, color: BrandColors.mut2)),
                ),
              )
            else
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) Divider(height: 1, color: BrandColors.line),
                Container(
                  key: Key('prof-clinic-row-${rows[i].name}'),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 10),
                  color: i.isOdd
                      ? BrandColors.surface2.withValues(alpha: .55)
                      : null,
                  child: Row(children: [
                    Expanded(
                      flex: 2,
                      child: Text(rows[i].name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: fs - .5,
                              fontWeight: FontWeight.w800,
                              color: BrandColors.brandText)),
                    ),
                    _numCell(n(rows[i].revenue),
                        color: BrandColors.goldDark, fs: fs),
                    _numCell(n(rows[i].doctor),
                        color: BrandColors.green, fs: fs),
                    _numCell(n(rows[i].clinicShare),
                        color: BrandColors.brand600, fs: fs),
                  ]),
                ),
              ],
          ],
        ),
      ),
    );
  }
}

/// م178 — جدول الإجمالي العام: المصروفات تحت عمود ربح العيادة والصافي
/// تحتها مباشرة — طرحٌ عمودي مقروء (نفس أرقام البطاقة السابقة حرفياً).
class ProfitsGrandTable extends StatelessWidget {
  const ProfitsGrandTable({
    super.key,
    required this.revenue,
    required this.doctor,
    required this.clinic,
    required this.expenses,
    this.title = 'الإجمالي العام لجميع العيادات',
    this.dense = false,
  });

  final num revenue;
  final num doctor;
  final num clinic;
  final num expenses;
  final String title;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final n = formatNumber;
    final fs = dense ? 12.0 : 12.5;

    Widget row(String label, Widget c1, Widget c2, Widget c3,
        {Key? key, bool emphasize = false}) {
      return Container(
        key: key,
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: emphasize
            ? BoxDecoration(
                color: const Color.fromRGBO(46, 125, 90, .08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color.fromRGBO(46, 125, 90, .25)),
              )
            : null,
        child: Row(children: [
          Expanded(
            flex: 2,
            child: Text(label,
                style: TextStyle(
                    fontSize: fs - .5,
                    fontWeight: FontWeight.w800,
                    color: BrandColors.brandText)),
          ),
          c1,
          c2,
          c3,
        ]),
      );
    }

    final dash = _numCell('—', color: BrandColors.mut2, fs: fs);
    Widget spacer() => const Expanded(child: SizedBox());

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: BrandColors.gold, width: 1.5),
      ),
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                      color: BrandColors.goldDark)),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(children: [
                const Expanded(flex: 2, child: SizedBox()),
                _headCell('الإيراد'),
                _headCell('ربح الطبيب'),
                _headCell('ربح العيادة'),
              ]),
            ),
            const SizedBox(height: 4),
            Divider(height: 1, color: BrandColors.line),
            row(
              'الإجمالي',
              _numCell(n(revenue),
                  color: BrandColors.goldDark,
                  bold: true,
                  fs: fs,
                  key: const Key('prof-grand-revenue')),
              _numCell(n(doctor),
                  color: BrandColors.green,
                  bold: true,
                  fs: fs,
                  key: const Key('prof-grand-doctor')),
              _numCell(n(clinic),
                  color: BrandColors.brand600,
                  bold: true,
                  fs: fs,
                  key: const Key('prof-grand-clinic')),
            ),
            Divider(height: 1, color: BrandColors.line),
            // صف المصروفات: قيمته تحت عمود ربح العيادة حصراً (طلب المالك).
            row(
              'المصروفات (−)',
              spacer(),
              dash,
              _numCell(n(expenses),
                  color: BrandColors.red,
                  bold: true,
                  fs: fs,
                  key: const Key('prof-grand-exp')),
              key: const Key('prof-grand-exp-row'),
            ),
            const SizedBox(height: 8),
            row(
              'صافي ربح العيادة',
              spacer(),
              dash,
              _numCell(n(clinic - expenses),
                  color: BrandColors.brand900,
                  bold: true,
                  fs: fs,
                  key: const Key('prof-grand-clinic-net')),
              emphasize: true,
            ),
          ],
        ),
      ),
    );
  }
}

/// م178 — جدول الأرباح والخسائر السنوي: صفٌّ لكل شهر + إجمالي السنة.
/// الشهر الحالي مميز بخلفية ذهبية خفيفة، والأشهر الفارغة باهتة.
class YearPnlTable extends StatelessWidget {
  const YearPnlTable({
    super.key,
    required this.report,
    this.dense = false,
  });

  final YearReport report;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final n = formatNumber;
    final fs = dense ? 11.0 : 12.0;
    final now = DateTime.now();
    final nowM = '${now.year}-${'${now.month}'.padLeft(2, '0')}';

    Widget row(MonthProfitRow m) {
      final muted = m.isEmpty;
      final cur = m.month == nowM;
      Color? c(Color base) => muted ? BrandColors.mut2 : base;
      return Container(
        key: Key('prof-pnl-${m.month}'),
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: cur
            ? BoxDecoration(
                color: BrandColors.gold.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(8),
              )
            : null,
        child: Row(children: [
          SizedBox(
            width: dense ? 52 : 66,
            child: Text(dense ? arMonths[m.idx].substring(0, 4) : arMonths[m.idx],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: fs - .5,
                    fontWeight:
                        cur ? FontWeight.w900 : FontWeight.w800,
                    color: muted
                        ? BrandColors.mut2
                        : BrandColors.brandText)),
          ),
          _numCell(muted ? '—' : n(m.revenue),
              color: c(BrandColors.goldDark), fs: fs),
          _numCell(muted ? '—' : n(m.doctor),
              color: c(BrandColors.green), fs: fs),
          _numCell(muted ? '—' : n(m.clinic),
              color: c(BrandColors.brand600), fs: fs),
          _numCell(muted ? '—' : n(m.expenses),
              color: c(BrandColors.red), fs: fs),
          _numCell(muted ? '—' : n(m.net),
              color: c(BrandColors.brand900), bold: true, fs: fs),
        ]),
      );
    }

    return Card(
      key: const Key('prof-pnl-table'),
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Text('الأرباح والخسائر — سنة ${report.year}',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: BrandColors.brandText)),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(children: [
                SizedBox(
                    width: dense ? 52 : 66,
                    child: Text('الشهر', style: _headStyle())),
                _headCell('الإيراد'),
                _headCell('الطبيب'),
                _headCell('العيادة'),
                _headCell('المصروفات'),
                _headCell('الصافي'),
              ]),
            ),
            const SizedBox(height: 4),
            Divider(height: 1, color: BrandColors.line),
            for (var i = 0; i < report.months.length; i++) ...[
              if (i > 0) Divider(height: 1, color: BrandColors.line),
              row(report.months[i]),
            ],
            const SizedBox(height: 8),
            // صف إجمالي السنة — مميز كصف صافي الخزينة.
            Container(
              key: const Key('prof-pnl-total'),
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 10),
              decoration: BoxDecoration(
                color: const Color.fromRGBO(46, 125, 90, .08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color.fromRGBO(46, 125, 90, .25)),
              ),
              child: Row(children: [
                SizedBox(
                  width: dense ? 52 : 66,
                  child: Text('السنة',
                      style: TextStyle(
                          fontSize: fs - .5,
                          fontWeight: FontWeight.w900,
                          color: BrandColors.brandText)),
                ),
                _numCell(n(report.revenue),
                    color: BrandColors.goldDark, bold: true, fs: fs),
                _numCell(n(report.doctor),
                    color: BrandColors.green, bold: true, fs: fs),
                _numCell(n(report.clinic),
                    color: BrandColors.brand600, bold: true, fs: fs),
                _numCell(n(report.expenses),
                    color: BrandColors.red, bold: true, fs: fs),
                _numCell(n(report.net),
                    color: BrandColors.brand900, bold: true, fs: fs),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

/// م178 — بيانات مؤشر سنوي واحد.
class YearKpi {
  const YearKpi(this.label, this.value, this.color, {this.keyId, this.yoy});

  final String label;
  final String value;
  final Color color;
  final String? keyId;

  /// نسبة التغير عن السنة السابقة (null = لا أساس).
  final num? yoy;
}

/// م178 — بطاقات مؤشرات السنة: شبكة عمودين هاتفياً وشريط أفقي كمبيوترياً.
class YearKpiCards extends StatelessWidget {
  const YearKpiCards({super.key, required this.items, this.wide = false});

  final List<YearKpi> items;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    Widget card(YearKpi k) => Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: BrandColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(k.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      TextStyle(fontSize: 10.5, color: BrandColors.mut2)),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(k.value,
                    key: k.keyId == null ? null : Key(k.keyId!),
                    style: TextStyle(
                        fontSize: wide ? 17 : 15,
                        fontWeight: FontWeight.w900,
                        color: k.color,
                        fontFeatures: const [
                          FontFeature.tabularFigures()
                        ])),
              ),
              if (k.yoy != null) ...[
                const SizedBox(height: 3),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(
                      k.yoy! >= 0
                          ? Icons.trending_up_rounded
                          : Icons.trending_down_rounded,
                      size: 12,
                      color: k.yoy! >= 0
                          ? BrandColors.green
                          : BrandColors.red),
                  const SizedBox(width: 3),
                  Text(
                      '${k.yoy! >= 0 ? '+' : ''}${k.yoy!.toStringAsFixed(1)}٪ عن السابقة',
                      style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: k.yoy! >= 0
                              ? BrandColors.green
                              : BrandColors.red)),
                ]),
              ],
            ],
          ),
        );

    if (wide) {
      return Row(children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: card(items[i])),
        ],
      ]);
    }
    // هاتف: شبكة عمودين متساوية الارتفاع لكل صف (IntrinsicHeight تمنح
    // الصف ارتفاعاً محدوداً كي يعمل stretch داخل عمود غير محدود).
    return Column(children: [
      for (var i = 0; i < items.length; i += 2) ...[
        if (i > 0) const SizedBox(height: 8),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: card(items[i])),
              const SizedBox(width: 8),
              if (i + 1 < items.length)
                Expanded(child: card(items[i + 1]))
              else
                const Expanded(child: SizedBox()),
            ],
          ),
        ),
      ],
    ]);
  }
}
