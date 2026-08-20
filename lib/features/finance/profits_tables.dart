/// م178 — جداول الأرباح المشتركة بين المنصتين (بهوية جداول الخزينة م154):
///
/// • [ProfitsClinicsTable] — جدول أرباح العيادات المنظم (العيادة/الإيراد/
///   ربح الطبيب/ربح العيادة) بدل البطاقات — شهرياً أو سنوياً.
/// • [ProfitsGrandTable] — جدول «الإجمالي العام»: صف الإجمالي، ثم صف
///   «المصروفات» بقيمته **تحت عمود ربح العيادة** فيقرأ الطرح عمودياً،
///   ثم صف «صافي ربح العيادة» المميز (طلب المالك — سهولة الحساب).
/// • [YearPnlTable] — جدول الأرباح والخسائر السنوي: 12 شهراً + صف السنة.
///   م190: نموذجان — **الكامل** (الإيراد/المختبرات/بعد المختبرات/الطبيب/
///   العيادة/المصروفات/التحاليل/**صافي العيادة** المظلَّل) و**المختصر**
///   للهاتف (إيرادٌ بعد المختبرات، بلا مصروفات، وصافٍ شامل بعلامة شرح)،
///   و[showYearPnlFullSheet] تفتح الكامل بتمريرٍ أفقي من الهاتف.
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
    this.showDoctor = true,
  });

  final String title;
  final List<ClinicProfitRow> rows;
  final bool dense;

  /// م180 — ميزة النسب مطفأة ⇒ يبقى عمود الإيراد وحده (كله للعيادة):
  /// عمودا «ربح الطبيب/ربح العيادة» يختفيان تماماً.
  final bool showDoctor;

  @override
  Widget build(BuildContext context) {
    final n = formatNumber;
    final fs = dense ? 12.0 : 12.5;
    // م187 — هل لأي عيادة قيمةُ مختبرات؟ (يقرّر ظهور العمود).
    final anyLab = rows.any((r) => r.lab > 0);
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
                // م187 — عمود المختبرات: يظهر فقط حين لأي عيادة قيمةُ معمل
                // (فلا يُزحم الجدول في العيادات التي لا تركيبات فيها).
                if (anyLab) _headCell('المختبرات'),
                if (showDoctor) _headCell('ربح الطبيب'),
                if (showDoctor) _headCell('ربح العيادة'),
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
                    if (anyLab)
                      _numCell(
                          rows[i].lab > 0 ? n(rows[i].lab) : '—',
                          color: rows[i].lab > 0
                              ? BrandColors.red
                              : BrandColors.mut2,
                          fs: fs),
                    if (showDoctor)
                      _numCell(n(rows[i].doctor),
                          color: BrandColors.green, fs: fs),
                    if (showDoctor)
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
    this.lab = 0,
    this.analyses = 0,
    this.title = 'الإجمالي العام لجميع العيادات',
    this.dense = false,
    this.showDoctor = true,
  });

  /// م180 — الميزة مطفأة ⇒ الإجمالي كله للعيادة: عمود قيمة واحد
  /// (الإجمالي/المصروفات/الصافي) بلا أعمدة طبيب/عيادة.
  final bool showDoctor;

  final num revenue;
  final num doctor;
  final num clinic;
  final num expenses;

  /// م187 — قيمة المختبرات (بلاغ المالك: «الإجمالي بعد تحديد النسبة يبقى
  /// فرق قيمة المعمل»). سببه أن المعمل يُخصم **قبل** تقسيم النِّسَب، فالإيراد
  /// يحويه والحصتان لا — فبقي الفرق بلا صفٍّ يفسّره. صفّاه أدناه («قيمة
  /// المختبرات» ثم «صافي بعد المختبرات») يجعلان الجدول متحقِّقاً من نفسه:
  /// صافي بعد المختبرات = ربح الطبيب + ربح العيادة **حتماً**.
  final num lab;

  /// م188 — إيراد التحاليل الثلاثية: **إيرادٌ خاصٌّ بالعيادة** (قرار
  /// المالك) — يُضاف صفّاً تحت المصروفات ولا يدخل عمود «الإيراد» ولا
  /// «ربح الطبيب»، ثم يُعاد جمع صافي ربح العيادة.
  final num analyses;
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
            if (showDoctor) ...[
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
              // م187 — صفّ المختبرات: قيمته تحت عمود **الإيراد** لأنها
              // تُخصم منه (كما وُضعت المصروفات تحت عمود ربح العيادة).
              if (lab > 0)
                row(
                  'قيمة المختبرات (−)',
                  _numCell(n(lab),
                      color: BrandColors.red,
                      bold: true,
                      fs: fs,
                      key: const Key('prof-grand-lab')),
                  dash,
                  dash,
                  key: const Key('prof-grand-lab-row'),
                ),
              if (lab > 0)
                row(
                  'صافي بعد المختبرات',
                  _numCell(n(revenue - lab),
                      color: BrandColors.brand900,
                      bold: true,
                      fs: fs,
                      key: const Key('prof-grand-after-lab')),
                  _numCell(n(doctor), color: BrandColors.green, fs: fs),
                  _numCell(n(clinic), color: BrandColors.brand600, fs: fs),
                  key: const Key('prof-grand-after-lab-row'),
                ),
              if (lab > 0) Divider(height: 1, color: BrandColors.line),
              // صف المصروفات: قيمته تحت عمود ربح العيادة (طلب المالك).
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
              // م188 — إيراد التحاليل: قيمته تحت عمود **ربح العيادة**
              // (كالمصروفات) لأنه يُضاف إليه وحده — وعمود الطبيب شرطة
              // إذ لا حصة له فيه.
              if (analyses > 0)
                row(
                  'إيراد التحاليل (+)',
                  spacer(),
                  dash,
                  _numCell(n(analyses),
                      color: BrandColors.green,
                      bold: true,
                      fs: fs,
                      key: const Key('prof-grand-analyses')),
                  key: const Key('prof-grand-analyses-row'),
                ),
              const SizedBox(height: 8),
              row(
                'صافي ربح العيادة',
                spacer(),
                dash,
                _numCell(n(clinic - expenses + analyses),
                    color: BrandColors.brand900,
                    bold: true,
                    fs: fs,
                    key: const Key('prof-grand-clinic-net')),
                emphasize: true,
              ),
            ] else ...[
              // م180 — الميزة مطفأة: الإجمالي كله للعيادة — عمود قيمة
              // واحد، والصافي = الإيراد − المصروفات (لا حصص إطلاقاً).
              Divider(height: 1, color: BrandColors.line),
              row(
                'الإجمالي',
                spacer(),
                spacer(),
                _numCell(n(revenue),
                    color: BrandColors.goldDark,
                    bold: true,
                    fs: fs,
                    key: const Key('prof-grand-revenue')),
              ),
              Divider(height: 1, color: BrandColors.line),
              // م187 — المختبرات تُخصم من الإجمالي في هذا الفرع أيضاً:
              // النِّسَب مطفأة ⇒ كل الصافي للعيادة، لكن المعمل كلفةٌ فعلية.
              if (lab > 0)
                row(
                  'قيمة المختبرات (−)',
                  spacer(),
                  spacer(),
                  _numCell(n(lab),
                      color: BrandColors.red,
                      bold: true,
                      fs: fs,
                      key: const Key('prof-grand-lab')),
                  key: const Key('prof-grand-lab-row'),
                ),
              if (lab > 0)
                row(
                  'صافي بعد المختبرات',
                  spacer(),
                  spacer(),
                  _numCell(n(revenue - lab),
                      color: BrandColors.brand900,
                      bold: true,
                      fs: fs,
                      key: const Key('prof-grand-after-lab')),
                  key: const Key('prof-grand-after-lab-row'),
                ),
              if (lab > 0) Divider(height: 1, color: BrandColors.line),
              row(
                'المصروفات (−)',
                spacer(),
                spacer(),
                _numCell(n(expenses),
                    color: BrandColors.red,
                    bold: true,
                    fs: fs,
                    key: const Key('prof-grand-exp')),
                key: const Key('prof-grand-exp-row'),
              ),
              // م188 — الفرع المطفأ النِّسَب: عمودُ قيمةٍ واحد، فالتحاليل
              // تُضاف فيه هي أيضاً — وإلا غاب إيرادها عن هذه الحالة.
              if (analyses > 0)
                row(
                  'إيراد التحاليل (+)',
                  spacer(),
                  spacer(),
                  _numCell(n(analyses),
                      color: BrandColors.green,
                      bold: true,
                      fs: fs,
                      key: const Key('prof-grand-analyses')),
                  key: const Key('prof-grand-analyses-row'),
                ),
              const SizedBox(height: 8),
              row(
                'صافي العيادة',
                spacer(),
                spacer(),
                _numCell(n(revenue - lab - expenses + analyses),
                    color: BrandColors.brand900,
                    bold: true,
                    fs: fs,
                    key: const Key('prof-grand-clinic-net')),
                emphasize: true,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// م178 — جدول الأرباح والخسائر السنوي: صفٌّ لكل شهر + إجمالي السنة.
/// الشهر الحالي مميز بخلفية ذهبية خفيفة، والأشهر الفارغة باهتة.
///
/// م190 — إعادة تصميمٍ بطلب المالك: الجدول صار **قصةً تُقرأ بنظرة** من
/// اليمين لليسار: الإيراد ← ما يُخصم منه (المختبرات) ← صافيه ← الحصتان ←
/// المصروفات ← ما يُضاف (التحاليل) ← **صافي إيراد العيادة** مظلَّلاً آخِراً.
/// فما كان أسطراً تحت الجدول (المختبرات/صافيها/التحاليل) صار أعمدةً في
/// موضعه من المعادلة — وحُذفت الأسطر.
///
/// نموذجان من مصدرٍ واحد ([full]):
///  • **الكامل** (الكمبيوتر، والهاتف عند التكبير): كل الأعمدة.
///  • **المختصر** (الهاتف افتراضاً): الشهر/الإيراد **بعد المختبرات**/
///    الطبيب/العيادة/الصافي — بلا عمود مصروفات (مطويٌّ داخل الصافي)،
///    وعلامةُ توضيحٍ بجوار «الصافي» تفتح معادلته **بأرقام الصفّ نفسه**.
///
/// عمودا المختبرات والتحاليل يظهران في الكامل **فقط حين لهما قيمة** في
/// السنة — فلا يُزحم الجدول بعمودَي أصفار.
class YearPnlTable extends StatelessWidget {
  const YearPnlTable({
    super.key,
    required this.report,
    this.dense = false,
    this.showDoctor = true,
    this.full = true,
    this.showTitle = true,
  });

  final YearReport report;
  final bool dense;

  /// م190 — عنوان البطاقة: يُخفى داخل ورقة التكبير (لها عنوانها الخاص،
  /// وعنوانُ جدولٍ أعرضَ من الورقة يبدو مقصوصاً).
  final bool showTitle;

  /// م180 — الميزة مطفأة ⇒ تختفي أعمدة الحصص (الإجمالي كله للعيادة).
  final bool showDoctor;

  /// م190 — النموذج الكامل (كل الأعمدة) أم المختصر (الهاتف).
  final bool full;

  @override
  Widget build(BuildContext context) {
    final n = formatNumber;
    final fs = dense ? 11.0 : 12.0;
    final now = DateTime.now();
    final nowM = '${now.year}-${'${now.month}'.padLeft(2, '0')}';
    final showLab = full && report.lab > 0;
    final showAnal = full && report.analyses > 0;
    final wMonth = dense ? 46.0 : 60.0;

    // خلفية عمود الصافي الأخير — تظليلٌ خفيف بلون صف السنة (طلب المالك)
    // يجعل عمود النتيجة مقروءاً بلا بحثٍ عنه.
    const netTint = Color.fromRGBO(46, 125, 90, .07);

    /// خلية رقمية داخل عمود الصافي المظلَّل (الخلفية تملأ ارتفاع الصف).
    /// [onTap] يجعلها قابلةً للضغط لشرح المعادلة — ويبقى الغلاف Expanded
    /// دائماً فلا ينكسر التخطيط داخل صفٍّ غير محدود العرض.
    Widget netCell(String txt,
            {bool bold = true, Color? color, Key? key, VoidCallback? onTap}) =>
        Expanded(
          child: GestureDetector(
            key: key,
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: Container(
              color: netTint,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(txt,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: fs,
                        fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
                        color: color ?? BrandColors.brand900,
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ),
            ),
          ),
        );

    /// نافذة «من أين جاء الصافي؟» — معادلةٌ بأرقام الصفّ المضغوط عليه.
    void explainNet(BuildContext ctx, String label, num revenue, num lab,
        num doctor, num clinic, num expenses, num analyses, num net) {
      Widget line(String t, String v, Color col, {bool bold = false}) =>
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Expanded(
                child: Text(t,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
                        color: bold ? BrandColors.brandText : BrandColors.mut)),
              ),
              Text(n(v),
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: col,
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ]),
          );
      showDialog<void>(
        context: ctx,
        builder: (_) => AlertDialog(
          key: const Key('prof-pnl-net-help'),
          title: Text('صافي $label — من أين جاء؟',
              style: const TextStyle(
                  fontSize: 14.5, fontWeight: FontWeight.w900)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            line('الإيراد المقبوض', '$revenue', BrandColors.goldDark),
            if (lab > 0) line('− قيمة المختبرات', '$lab', BrandColors.red),
            if (lab > 0)
              line('= صافي بعد المختبرات', '${revenue - lab}',
                  BrandColors.brand900),
            if (showDoctor) line('− حصة الطبيب', '$doctor', BrandColors.green),
            if (showDoctor)
              line('= حصة العيادة', '$clinic', BrandColors.brand600),
            line('− المصروفات', '$expenses', BrandColors.red),
            if (analyses > 0)
              line('+ إيراد التحاليل (للعيادة)', '$analyses',
                  BrandColors.green),
            const Divider(height: 14),
            line('صافي إيراد العيادة', '$net', BrandColors.brand900,
                bold: true),
          ]),
          actions: [
            TextButton(
              key: const Key('prof-pnl-net-help-ok'),
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('حسناً'),
            ),
          ],
        ),
      );
    }

    Widget row(MonthProfitRow m) {
      final muted = m.isEmpty;
      final cur = m.month == nowM;
      Color? c(Color base) => muted ? BrandColors.mut2 : base;
      final net = showDoctor ? m.net : m.netOff;
      return Container(
        key: Key('prof-pnl-${m.month}'),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: cur
            ? BoxDecoration(
                color: BrandColors.gold.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(8),
              )
            : null,
        child: Row(children: [
          SizedBox(
            width: wMonth,
            child: Text(
                dense ? arMonths[m.idx].substring(0, 4) : arMonths[m.idx],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: fs - .5,
                    fontWeight: cur ? FontWeight.w900 : FontWeight.w800,
                    color:
                        muted ? BrandColors.mut2 : BrandColors.brandText)),
          ),
          // م190 — المختصر يعرض الإيراد **بعد المختبرات** تحت نفس الاسم
          // (طلب المالك): فالرقم الذي يراه الطبيب هو ما تقسّمه النِّسَب.
          _numCell(muted ? '—' : n(full ? m.revenue : m.afterLab),
              color: c(BrandColors.goldDark), fs: fs),
          if (showLab)
            _numCell(muted || m.lab == 0 ? '—' : n(m.lab),
                color: c(BrandColors.red), fs: fs),
          if (showLab)
            _numCell(muted ? '—' : n(m.afterLab),
                color: c(BrandColors.brand900), fs: fs),
          if (showDoctor)
            _numCell(muted ? '—' : n(m.doctor),
                color: c(BrandColors.green), fs: fs),
          if (showDoctor)
            _numCell(muted ? '—' : n(m.clinic),
                color: c(BrandColors.brand600), fs: fs),
          // المصروفات: عمودٌ في الكامل، ومطويٌّ في المختصر داخل الصافي.
          if (full)
            _numCell(muted ? '—' : n(m.expenses),
                color: c(BrandColors.red), fs: fs),
          if (showAnal)
            _numCell(muted || m.analyses == 0 ? '—' : n(m.analyses),
                color: c(BrandColors.green), fs: fs),
          // الصافي: مظلَّلٌ دائماً، وبالضغط تُشرح معادلته بأرقام الشهر.
          netCell(muted ? '—' : n(net),
              key: Key('prof-pnl-net-${m.month}'),
              color: muted ? BrandColors.mut2 : null,
              onTap: muted
                  ? null
                  : () => explainNet(context, arMonths[m.idx], m.revenue,
                      m.lab, m.doctor, m.clinic, m.expenses, m.analyses, net)),
        ]),
      );
    }

    Widget headCell(String t) => Expanded(
        child: Text(t,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _headStyle()));

    return Card(
      key: const Key('prof-pnl-table'),
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showTitle) ...[
              Center(
                child: Text('الأرباح والخسائر — سنة ${report.year}',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: BrandColors.brandText)),
              ),
              const SizedBox(height: 10),
            ],
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(children: [
                SizedBox(
                    width: wMonth,
                    child: Text('الشهر', style: _headStyle())),
                headCell('الإيراد'),
                if (showLab) headCell('المختبرات'),
                if (showLab) headCell('بعد المختبرات'),
                if (showDoctor) headCell('الطبيب'),
                if (showDoctor) headCell('العيادة'),
                if (full) headCell('المصروفات'),
                if (showAnal) headCell('التحاليل'),
                Expanded(
                  child: Container(
                    color: netTint,
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(full ? 'صافي العيادة' : 'الصافي',
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _headStyle()),
                          ),
                          // م190 — علامة التوضيح (طلب المالك): تشرح
                          // المعادلة بأرقام **السنة** هنا، وبأرقام الشهر
                          // عند الضغط على خليته.
                          InkWell(
                            key: const Key('prof-pnl-net-info'),
                            onTap: () => explainNet(
                                context,
                                'سنة ${report.year}',
                                report.revenue,
                                report.lab,
                                report.doctor,
                                report.clinic,
                                report.expenses,
                                report.analyses,
                                showDoctor ? report.net : report.netOff),
                            child: Padding(
                              padding: const EdgeInsets.only(right: 2),
                              child: Icon(Icons.info_outline_rounded,
                                  size: 13, color: BrandColors.brand600),
                            ),
                          ),
                        ]),
                  ),
                ),
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
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: const Color.fromRGBO(46, 125, 90, .08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color.fromRGBO(46, 125, 90, .25)),
              ),
              child: Row(children: [
                SizedBox(
                  width: wMonth,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text('السنة',
                        style: TextStyle(
                            fontSize: fs - .5,
                            fontWeight: FontWeight.w900,
                            color: BrandColors.brandText)),
                  ),
                ),
                _numCell(n(full ? report.revenue : report.afterLab),
                    color: BrandColors.goldDark, bold: true, fs: fs),
                if (showLab)
                  _numCell(n(report.lab),
                      color: BrandColors.red,
                      bold: true,
                      fs: fs,
                      key: const Key('prof-pnl-lab')),
                if (showLab)
                  _numCell(n(report.afterLab),
                      color: BrandColors.brand900,
                      bold: true,
                      fs: fs,
                      key: const Key('prof-pnl-after-lab')),
                if (showDoctor)
                  _numCell(n(report.doctor),
                      color: BrandColors.green, bold: true, fs: fs),
                if (showDoctor)
                  _numCell(n(report.clinic),
                      color: BrandColors.brand600, bold: true, fs: fs),
                if (full)
                  _numCell(n(report.expenses),
                      color: BrandColors.red, bold: true, fs: fs),
                if (showAnal)
                  _numCell(n(report.analyses),
                      color: BrandColors.green,
                      bold: true,
                      fs: fs,
                      key: const Key('prof-pnl-analyses')),
                netCell(n(showDoctor ? report.net : report.netOff)),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

/// م190 — الجدول الكامل في ورقةٍ ملء الشاشة (الهاتف): كل أعمدة الكمبيوتر
/// بعرضٍ مريح ثابت مع **تمريرٍ أفقي** عادي — فالمعلومة كاملةٌ متى أرادها،
/// والأساس يبقى الجدول المختصر (طلب المالك).
Future<void> showYearPnlFullSheet(
  BuildContext context, {
  required YearReport report,
  required bool showDoctor,
}) {
  // عرضٌ ثابتٌ يتّسع لكل الأعمدة: الشهر + ثمانية أعمدة رقمية بحدٍّ مريح.
  final cols = 1 +
      (report.lab > 0 ? 2 : 0) +
      (showDoctor ? 2 : 0) +
      1 +
      (report.analyses > 0 ? 1 : 0) +
      1;
  final width = 60.0 + cols * 96.0;
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      key: const Key('prof-pnl-full-sheet'),
      insetPadding: const EdgeInsets.all(10),
      backgroundColor: BrandColors.surface,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 0),
          child: Row(children: [
            Expanded(
              child: Text('الجدول الكامل — سنة ${report.year}',
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                      color: BrandColors.brandText)),
            ),
            IconButton(
              key: const Key('prof-pnl-full-close'),
              icon: const Icon(Icons.close_rounded, size: 20),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ]),
        ),
        Flexible(
          child: SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: width,
                child: YearPnlTable(
                    report: report,
                    dense: true,
                    showDoctor: showDoctor,
                    showTitle: false),
              ),
            ),
          ),
        ),
      ]),
    ),
  );
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
