/// قوالب PDF العربية — نقل مطبوعات الأصل الثلاث فوق خط القاهرة المُثبت
/// (إثبات م0: التشكيل سليم على pdf 3.13.0 بمسار legacy presentation-forms):
///   • تقرير الشهر (printMonth في ArchiveTab): ملخص، جداول المعالجات
///     المجمّعة بلقطات النسب، جدول التركيبات بالنسبة الفعلية، الإجمالي
///     المجمّع، وصندوق الديون المعلقة.
///   • تقرير المختبر (printLab في LabsTab): جدول الحالات + المجاميع.
///   • تقرير الأسنان (printReport في ToothReport): بيانات المريض، جدول
///     المعالجات بالأسنان، الإجمالي، التشخيص/الملاحظات/الأمراض، والتواقيع.
/// البناة دوال نقية (بايتات خطوط ← بايتات PDF) — قابلة للاختبار بلا منصة.
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/utils/js_compat.dart';
import '../archive/month_stats.dart' show MonthData;
import '../finance/treasury_logic.dart'
    show ProsCaseRow, ProsGroup, prosPayLab, prosPayDoc, prosPayClin;
import '../labs/labs_logic.dart';
import '../records/tooth_notation.dart'
    show NotationSystem, toothLabelFromTooth;
import '../records/tooth_summary.dart'
    show ToothGroupLabel, ToothCrossModel;
import 'treatment_tables.dart';
import '../../data/audit/audit_trail.dart' show currentAuditStaffDisplay;

typedef JMap = Map<String, Object?>;

// م107 — نظام المستند المحاسبي الأحادي (قرار المالك باللقطات): **لا
// تعبئة داكنة إطلاقاً**. عناوين الأقسام نصٌّ أسود فوق خطٍّ فاصل، رؤوس
// الجداول رمادي فاتح جداً بنصٍّ أسود (نمط دفتر الأستاذ)، التظليل
// المتناوب فاتح، والحدود شعيرات رمادية — أبيض وأسود ورمادي فاتح فقط.
const _hdrBg = PdfColor.fromInt(0xFFF2F2F2); // رأس جدول فاتح (كان داكناً)
const _brand900 = _hdrBg;
const _brand600 = PdfColors.black;
const _ink = PdfColor.fromInt(0xFF111111);
const _mut = PdfColor.fromInt(0xFF666666);
const _line = PdfColor.fromInt(0xFFD9D9D9);
// م107 — صندوق التنبيه أحادي أيضاً: رمادي فاتح بنص أسود عريض.
const _warnBg = PdfColor.fromInt(0xFFF2F2F2);
const _warnBd = PdfColor.fromInt(0xFF999999);
const _warnTx = PdfColors.black;

class PdfFonts {
  const PdfFonts({required this.regular, required this.bold, this.fallback});

  final ByteData regular;
  final ByteData bold;

  /// دفعة أول/ج (م67) — خط احتياطي كامل تغطية الأشكال العربية المعزولة.
  ///
  /// خط Cairo (وكل الخطوط المرفقة) ينقصه الشكل المعزول للياء U+FEF1 — وهو
  /// ما يصدره مشكّل bidi في حزمة pdf لياءٍ في آخر كلمة سبقها حرفٌ غير موصول
  /// (ا، د، ذ، ر، ز، و، ة). فكانت 23 من 31 اسماً عربياً شائعاً تُطبع ناقصةً،
  /// و«السكري» تصير «السكر» على تقرير طبي. حزمة pdf تحلّ الخط الاحتياطي
  /// **لكل محرف على حدة**، فيبقى مظهر Cairo لكل ما يرسمه، ويُستعار Amiri
  /// (تغطية 140/144 من كتلة FE70–FEFF) للمحرف المفقود وحده.
  final ByteData? fallback;

  pw.ThemeData theme() {
    final fb = fallback;
    final fallbacks = fb == null ? const <pw.Font>[] : [pw.Font.ttf(fb)];
    return pw.ThemeData.withFont(
      base: pw.Font.ttf(regular),
      bold: pw.Font.ttf(bold),
      fontFallback: fallbacks,
    );
  }
}

final _n = formatNumber;

pw.Widget _cell(String s,
        {bool bold = false, PdfColor? color, double size = 9}) =>
    pw.Padding(
      // م107 — حشوة الليدجر المضغوطة (5/3←4/2.5).
      padding:
          const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2.5),
      child: pw.Text(s,
          style: pw.TextStyle(
            fontSize: size,
            color: color ?? _ink,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          )),
    );

/// جدول RTL — التوأم البصري الحرفي لقالب pdf.service.js (م28):
///   • ترويسة **سوداء بنص أبيض** (thead {background:#000;color:#fff}).
///   • حدود رفيعة (#ccc) وصفوف متعرجة (#f5f5f5 للزوجية).
///   • صف المجموع #e8e8e8 غامق بحد علوي أسود 2px (.total-row).
///
/// **ترتيب RTL (إصلاح م27):** حزمة pdf لا تدعم اتجاه الأعمدة في pw.Table
/// إطلاقاً (تُخطّط دائماً يساراً-يميناً بترتيب المصفوفة)، فنعكس كل صف
/// عكساً موحّداً فيهبط العنصر الأول يميناً وتبقى كل خلية تحت عنوانها.
pw.Widget _table(List<String> headers, List<List<String>> rows,
    {List<String>? totRow,
    // م108 — عروض أعمدة ثابتة (بمؤشرات ما بعد عكس RTL): تمريرها يوحّد
    // الرصف بين جداول متتالية فيتراصف كل عمود تحت نظيره طول الورقة.
    Map<int, pw.TableColumnWidth>? columnWidths}) {
  List<String> rtl(List<String> cells) => cells.reversed.toList();
  pw.TableRow tr(List<String> cells,
          {bool head = false, bool total = false, bool zebra = false}) =>
      pw.TableRow(
        // م107 — رأسٌ فاتح بنصٍّ أسود بين خطّين (ليدجر)، مجموعٌ فاتح
        // بخطٍّ علوي أسود، وتظليل متناوب فاتح — لا أبيض على داكن بعد.
        decoration: head
            ? const pw.BoxDecoration(
                color: _hdrBg,
                border: pw.Border(
                    top: pw.BorderSide(
                        color: PdfColors.black, width: .9),
                    bottom: pw.BorderSide(
                        color: PdfColors.black, width: .9)),
              )
            : total
                ? const pw.BoxDecoration(
                    color: PdfColor.fromInt(0xFFF2F2F2),
                    border: pw.Border(
                        top: pw.BorderSide(
                            color: PdfColors.black, width: 1.2)),
                  )
                : zebra
                    ? const pw.BoxDecoration(
                        color: PdfColor.fromInt(0xFFF7F7F7))
                    : null,
        children: [
          for (final c in rtl(cells))
            _cell(c, bold: head || total, color: PdfColors.black),
        ],
      );
  return pw.Table(
    border: pw.TableBorder.all(
        color: const PdfColor.fromInt(0xFFD9D9D9), width: .6),
    columnWidths: columnWidths,
    defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
    children: [
      tr(headers, head: true),
      for (var i = 0; i < rows.length; i++)
        tr(rows[i], zebra: i.isOdd),
      if (totRow != null) tr(totRow, total: true),
    ],
  );
}

/// م107 — عنوان قسمٍ محاسبي: نصٌّ أسود عريض فوق خطٍّ فاصل رفيع —
/// بلا أي شريطٍ داكن (اعتراض المالك على .sec-title القديم).
pw.Widget _secTitle(String s, {bool centered = false}) => pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.only(top: 8, bottom: 3),
      padding: const pw.EdgeInsets.only(bottom: 2),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
            bottom: pw.BorderSide(color: PdfColors.black, width: .9)),
      ),
      // م108 — عناوين مجموعات الكشف في الوسط (طلب المالك).
      alignment: centered ? pw.Alignment.center : null,
      child: pw.Text(s,
          textAlign: centered ? pw.TextAlign.center : null,
          style: pw.TextStyle(
              fontSize: 10.5,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.black)),
    );

pw.Widget _h1(String s) => pw.Center(
    child: pw.Text(s,
        style: pw.TextStyle(
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.black)));

pw.Widget _sub(String s) => pw.Center(
    child: pw.Text(s,
        style: const pw.TextStyle(
            fontSize: 9, color: PdfColor.fromInt(0xFF555555))));

/// شعار الطباعة (من config.logo) — يضبطه loadPdfBrand قبل كل بناء.
Uint8List? pdfLogoBytes;

Future<Uint8List> _doc(PdfFonts fonts, List<pw.Widget> children) {
  final doc = pw.Document(theme: fonts.theme());
  final logo = pdfLogoBytes;
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    // م107 — هوامش أضيق (32←24): أقل ورق بنفس الوضوح.
    margin: const pw.EdgeInsets.all(24),
    textDirection: pw.TextDirection.rtl,
    build: (ctx) => [
      // م107 — خط ترويسة أسود رفيع بدل الشريط الرمادي الداكن.
      pw.Container(
          height: 2,
          color: PdfColors.black,
          margin: const pw.EdgeInsets.only(bottom: 6)),
      if (logo != null)
        pw.Center(
          child: pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 6),
            child: pw.Image(pw.MemoryImage(logo), height: 34),
          ),
        ),
      ...children,
      // م121 — هوية الطابع في كل تقرير (قرار المالك): سطر تذييل موحد
      // من هذه النقطة الوحيدة التي تمر بها كل الطباعات.
      if (currentAuditStaffDisplay.isNotEmpty) ...[
        pw.SizedBox(height: 12),
        pw.Container(height: 1, color: PdfColors.grey400),
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 3),
          child: pw.Text(
            'طبعه: $currentAuditStaffDisplay — ${_printStamp()}',
            style:
                const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700),
          ),
        ),
      ],
    ],
  ));
  return doc.save();
}

/// م121 — ختم وقت الطباعة للتذييل (سنة-شهر-يوم ساعة:دقيقة).
String _printStamp() {
  final d = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}

/// جدول عام بعنوان — لطباعات الخزينة وديون العيادة وأشباهها.
Future<Uint8List> simpleTablePdf(
  PdfFonts fonts, {
  required String title,
  String subtitle = '',
  required List<String> headers,
  required List<List<String>> rows,
  List<String>? totRow,
}) {
  return _doc(fonts, [
    _h1(title),
    if (subtitle.isNotEmpty) _sub(subtitle),
    pw.SizedBox(height: 8),
    _table(headers, rows, totRow: totRow),
  ]);
}

/// م106 — تقرير قفل اليوم الاحترافي (طلب المالك: طباعة منظمة للأرشفة
/// الشهرية في مصنف):
///   • ترويسة عريضة كبيرة «تقرير دخل <التاريخ>».
///   • جدول الدخل وحده (بلا خلط مصروفات) ثم صف إجمالياته المرتب بأعمدة
///     متوازية: الإجمالي (المدفوع) | كاش | تحويل | الدين المتبقي.
///   • جدول المصروفات المفصل منفصلاً، وصف إجمالياته **بنفس ترتيب
///     الأعمدة**: إجمالي المصروف | مصروف كاش | مصروف تحويل.
///   • ختام بارز: صافي دخل العيادة بعد الخصم | صافي كاش | صافي تحويل.
///   الأعمدة المتشابهة متناظرة بين الأقسام لسهولة الجمع اليدوي.
Future<Uint8List> dayClosePdf(
  PdfFonts fonts, {
  required String date,
  required String centerName,
  required String currency,
  required List<List<String>> incomeRows,
  required String totalPaid,
  required String cashPaid,
  required String transferPaid,
  required String debtRemaining,
  required List<List<String>> expenseRows,
  required String expenseTotal,
  required String expenseCash,
  required String expenseTransfer,
  required String netTotal,
  required String netCash,
  required String netTransfer,
}) {
  pw.Widget h2(String s) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 12, bottom: 4),
        child: pw.Text(s,
            style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.black)),
      );
  // جدول إجمالياتٍ من صفٍّ واحد: رأس بعناوين الأعمدة وصفٌّ معبأ بنمط
  // «المجموع» (عريض بخط علوي أسود) — فتصطف الأرقام تحت عناوينها بدقة.
  pw.Widget totals(List<String> headers, List<String> values) =>
      _table(headers, const [], totRow: values);

  return _doc(fonts, [
    // ترويسة عريضة كبيرة للأرشفة الشهرية.
    pw.Center(
        child: pw.Text('تقرير دخل $date',
            style: pw.TextStyle(
                fontSize: 19,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.black))),
    if (centerName.isNotEmpty) ...[
      pw.SizedBox(height: 2),
      _sub(centerName),
    ],
    pw.SizedBox(height: 10),
    h2('أولاً — دخل اليوم'),
    if (incomeRows.isEmpty)
      _sub('لا دخل مسجّل هذا اليوم')
    else
      _table(const [
        '#', 'الساعة', 'الاسم', 'العيادة', 'الدفع',
        'القيمة', 'المدفوع', 'المتبقي',
      ], incomeRows),
    pw.SizedBox(height: 5),
    totals(
      ['الإجمالي (المدفوع) $currency', 'كاش', 'تحويل', 'الدين المتبقي'],
      [totalPaid, cashPaid, transferPaid, debtRemaining],
    ),
    h2('ثانياً — المصروفات'),
    if (expenseRows.isEmpty)
      _sub('لا مصروفات مسجّلة هذا اليوم')
    else
      _table(const ['#', 'الساعة', 'البند', 'الفئة', 'الدفع', 'المبلغ'],
          expenseRows),
    pw.SizedBox(height: 5),
    totals(
      ['إجمالي المصروف', 'مصروف كاش', 'مصروف تحويل'],
      [expenseTotal, expenseCash, expenseTransfer],
    ),
    h2('ثالثاً — صافي دخل العيادة بعد خصم المصروف'),
    totals(
      ['الصافي $currency', 'صافي كاش', 'صافي تحويل'],
      [netTotal, netCash, netTransfer],
    ),
  ]);
}

// ── طباعة جداول المعالجات (تفصيل الخزينة كاش/تحويل) ─────────────────────────

/// م180 — نسخة الطباعة عند إطفاء ميزة النسب: أربعة أعمدة فقط
/// (التاريخ/الاسم/الإيراد/الدفع) بلا أي حصص ولا نسب في العناوين.
Future<Uint8List> _treatmentTablesPdfNoRates(
  PdfFonts fonts, {
  required String title,
  required String subtitle,
  required String currency,
  required TreatmentTables tables,
}) {
  final c = currency;
  final grid = <int, pw.TableColumnWidth>{
    0: const pw.FixedColumnWidth(48), // الدفع
    1: const pw.FixedColumnWidth(72), // الإيراد
    2: const pw.FlexColumnWidth(), // الاسم
    3: const pw.FixedColumnWidth(58), // التاريخ
  };
  const heads = ['التاريخ', 'الاسم', 'الإيراد', 'الدفع'];
  return _doc(fonts, [
    _h1(title),
    _sub(subtitle),
    for (final g in tables.groups) ...[
      _secTitle(g.service, centered: true),
      _table(
        heads,
        [
          for (final r in g.rows)
            [r.date, r.name, '${_n(r.amount)} $c', r.payment],
        ],
        totRow: ['المجموع', '', '${_n(g.revenue)} $c', ''],
        columnWidths: grid,
      ),
    ],
    pw.SizedBox(height: 8),
    pw.Table(
      border: pw.TableBorder.all(
          color: const PdfColor.fromInt(0xFFD9D9D9), width: .6),
      columnWidths: grid,
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(
            color: PdfColor.fromInt(0xFFF2F2F2),
            border: pw.Border(
                top: pw.BorderSide(color: PdfColors.black, width: 1.2)),
          ),
          children: [
            for (final v in [
              '', 'الإجمالي النهائي', '${_n(tables.revenue)} $c', '',
            ].reversed)
              _cell(v, bold: true, color: PdfColors.black),
          ],
        ),
      ],
    ),
  ]);
}


/// توأم طباعة تفصيل الخزينة في الأصل (TreasuryTab): جدول لكل معالجة
/// متشابهة بعنوان «نسبة الطبيب X% • نسبة العيادة Y%» وعمودي «طبيب/عيادة»،
/// وانهيار 0% للإيرادات فقط، ثم «الإجمالي النهائي» — الأعمدة بقرار
/// المالك (م28): **التاريخ أولاً ثم الاسم**.
Future<Uint8List> treatmentTablesPdf(
  PdfFonts fonts, {
  required String title,
  required String subtitle,
  required String currency,
  required TreatmentTables tables,
  // م180 — ميزة النسب مطفأة ⇒ عمودا «طبيب/عيادة» يختفيان من الطباعة
  // بالكامل وعناوين الجداول بلا نِسَب (الإجمالي كله للعيادة).
  bool showRates = true,
}) {
  final c = currency;
  if (!showRates) {
    return _treatmentTablesPdfNoRates(fonts,
        title: title,
        subtitle: subtitle,
        currency: currency,
        tables: tables);
  }
  // م108 — «تناظرٌ رهيب»: شبكة أعمدة واحدة مثبّتة لكل الجداول من أول
  // الورقة لآخرها (المؤشرات بعد عكس RTL: 0=الدفع .. 5=التاريخ) — فيقع
  // الإيراد تحت الإيراد وطبيب تحت طبيب وعيادة تحت عيادة طوال الصفحة،
  // ويهبط الإجمالي النهائي صفاً واحداً بنفس الشبكة تحت الأعمدة نفسها.
  final grid = <int, pw.TableColumnWidth>{
    0: const pw.FixedColumnWidth(48), // الدفع
    1: const pw.FixedColumnWidth(64), // عيادة
    2: const pw.FixedColumnWidth(64), // طبيب
    3: const pw.FixedColumnWidth(64), // الإيراد
    4: const pw.FlexColumnWidth(), // الاسم
    5: const pw.FixedColumnWidth(58), // التاريخ
  };
  const heads = ['التاريخ', 'الاسم', 'الإيراد', 'طبيب', 'عيادة', 'الدفع'];
  return _doc(fonts, [
    _h1(title),
    _sub(subtitle),
    for (final g in tables.groups) ...[
      _secTitle(
        g.zeroPct
            ? '${g.service} — الإيرادات فقط (نسبة الطبيب 0%)'
            : '${g.service} — طبيب ${g.effPct}% • عيادة ${100 - g.effPct}%',
        centered: true,
      ),
      _table(
        heads,
        [
          for (final r in g.rows)
            [
              r.date, r.name, '${_n(r.amount)} $c',
              // نسبة الصفر: شرطات بنفس الأعمدة حفاظاً على الرصف.
              g.zeroPct ? '—' : '${_n(r.doctor)} $c',
              g.zeroPct ? '—' : '${_n(r.clinic)} $c',
              r.payment,
            ],
        ],
        totRow: [
          'المجموع', '', '${_n(g.revenue)} $c',
          g.zeroPct ? '—' : '${_n(g.doctor)} $c',
          g.zeroPct ? '—' : '${_n(g.clinic)} $c', '',
        ],
        columnWidths: grid,
      ),
    ],
    pw.SizedBox(height: 8),
    // الإجمالي النهائي: صفٌّ واحد بنفس الشبكة — الإيرادات تحت عمود
    // الإيراد وربح الطبيب تحت طبيب وربح العيادة تحت عيادة (طلب المالك).
    pw.Table(
      border: pw.TableBorder.all(
          color: const PdfColor.fromInt(0xFFD9D9D9), width: .6),
      columnWidths: grid,
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(
            color: PdfColor.fromInt(0xFFF2F2F2),
            border: pw.Border(
                top: pw.BorderSide(color: PdfColors.black, width: 1.2)),
          ),
          children: [
            for (final v in [
              '', 'الإجمالي النهائي', '${_n(tables.revenue)} $c',
              '${_n(tables.doctor)} $c', '${_n(tables.clinic)} $c', '',
            ].reversed)
              _cell(v, bold: true, color: PdfColors.black),
          ],
        ),
      ],
    ),
  ]);
}

// ── تقرير الشهر ─────────────────────────────────────────────────────────────

Future<Uint8List> monthlyReportPdf(
  PdfFonts fonts, {
  required String month,
  required String centerName,
  required String currency,
  required MonthData data,
  required TreatmentTables recTables,
  required List<JMap> prosRows,
  required List<JMap> pendingDebts,
}) {
  final c = currency;
  final totClinShare =
      prosRows.fold<num>(0, (s, p) => s + jsNumOr0(p['clinicShare']));
  final prosProfit = data.prosDoc + totClinShare;
  // النسبة المعروضة = الفعلية المستخدمة (طبيب ÷ ربح) — لا 50 عامة أبداً.
  final effProsPct =
      prosProfit > 0 ? (data.prosDoc / prosProfit * 100).round() : 0;
  final hasRecs = recTables.groups.isNotEmpty;
  final pendingTotal =
      pendingDebts.fold<num>(0, (s, d) => s + jsNumOr0(d['remaining']));

  return _doc(fonts, [
    _h1('تقرير شهر $month'),
    _sub(centerName),
    _secTitle('الملخص'),
    _table(
      ['كاش', 'تحويل', 'تركيبات', 'الإجمالي'],
      [
        [
          '${_n(data.cash)} $c',
          '${_n(data.xfer)} $c',
          '${_n(data.prosTotal)} $c',
          '${_n(data.total)} $c',
        ],
      ],
    ),

    // ── السجلات: جدول مستقل لكل معالجة متشابهة، بعنوانٍ شريطي أسود
    //   يحمل نسبتي الطبيب/العيادة (تصميم Vue)، والأعمدة بقرار المالك
    //   (م28): **التاريخ أولاً ثم الاسم**.
    if (hasRecs) ...[
      for (final g in recTables.groups) ...[
        _secTitle(
          g.zeroPct
              ? '${g.service} — الإيرادات فقط (نسبة الطبيب 0%)'
              : '${g.service} — نسبة الطبيب ${g.effPct}% • نسبة العيادة ${100 - g.effPct}%',
        ),
        if (g.zeroPct)
          _table(
            ['التاريخ', 'الاسم', 'الإيراد', 'الدفع'],
            [
              for (final r in g.rows)
                [r.date, r.name, '${_n(r.amount)} $c', r.payment],
            ],
            totRow: ['المجموع', '', '${_n(g.revenue)} $c', ''],
          )
        else
          _table(
            [
              'التاريخ', 'الاسم', 'الإيراد',
              'طبيب (${g.effPct}%)', 'عيادة (${100 - g.effPct}%)', 'الدفع',
            ],
            [
              for (final r in g.rows)
                [
                  r.date, r.name, '${_n(r.amount)} $c',
                  '${_n(r.doctor)} $c', '${_n(r.clinic)} $c', r.payment,
                ],
            ],
            totRow: [
              'المجموع', '', '${_n(g.revenue)} $c',
              '${_n(g.doctor)} $c', '${_n(g.clinic)} $c', '',
            ],
          ),
      ],
      _secTitle('الإجمالي النهائي للمعالجات'),
      _table(
        ['', 'الإيرادات', 'ربح الطبيب', 'ربح العيادة'],
        const [],
        totRow: [
          'المجموع',
          '${_n(recTables.revenue)} $c',
          '${_n(recTables.doctor)} $c',
          '${_n(recTables.clinic)} $c',
        ],
      ),
    ],

    // ── التركيبات — التاريخ أولاً ثم الاسم (قرار المالك م28) ──
    if (prosRows.isNotEmpty) ...[
      _secTitle('التركيبات'),
      _table(
        [
          'التاريخ', 'الاسم', 'النوع', 'الإجمالي', 'المعمل',
          'طبيب ($effProsPct%)', 'عيادة (${100 - effProsPct}%)',
        ],
        [
          for (final p in prosRows)
            [
              '${p['date'] ?? ''}',
              '${p['name'] ?? ''}',
              'تركيبات',
              '${_n(p['total'])} $c',
              '${_n(p['labValue'])} $c',
              '${_n(p['doctorShare'])} $c',
              '${_n(p['clinicShare'])} $c',
            ],
        ],
        totRow: [
          'المجموع', '', '', '', '',
          '${_n(data.prosDoc)} $c', '${_n(totClinShare)} $c',
        ],
      ),
    ],

    // ── الإجمالي المجمّع ──
    if (hasRecs && prosRows.isNotEmpty) ...[
      pw.SizedBox(height: 8),
      _secTitle('الإجمالي المجمّع'),
      _table(
        [
          '', 'طبيب — معالجات', 'طبيب — تركيبات ($effProsPct%)',
          'إجمالي الطبيب', 'إجمالي العيادة',
        ],
        const [],
        totRow: [
          'المجموع',
          '${_n(recTables.doctor)} $c',
          '${_n(data.prosDoc)} $c',
          '${_n(recTables.doctor + data.prosDoc)} $c',
          '${_n(recTables.clinic + totClinShare)} $c',
        ],
      ),
    ],

    // ── الديون المعلقة ──
    if (pendingDebts.isNotEmpty)
      pw.Container(
        margin: const pw.EdgeInsets.only(top: 14),
        padding:
            const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: pw.BoxDecoration(
          color: _warnBg,
          border: pw.Border.all(color: _warnBd),
          borderRadius: pw.BorderRadius.circular(5),
        ),
        child: pw.Text(
          'ديون معلقة: ${pendingDebts.length} دين بإجمالي متبقٍ ${_n(pendingTotal)} $c',
          style: pw.TextStyle(
              fontSize: 10.5,
              color: _warnTx,
              fontWeight: pw.FontWeight.bold),
        ),
      ),
  ]);
}

// ── تقرير المختبر ───────────────────────────────────────────────────────────

/// v50 — تقرير التركيبات بتصميم جديد على هوية تقرير الكاش والتحويل:
/// صناديق إحصاء علوية (الحالات/الوحدات/إجمالي المخبر)، جدول برأس
/// رمادي غامق مع عمود «سعر الوحدة» لسهولة مراجعة الحساب (المخزن،
/// وإلا القيمة ÷ الوحدات)، صف مجموع مؤطر، وخلاصة مالية ختامية
/// بصناديق أنيقة — التوقيع البرمجي للدالة كما هو حرفياً.
/// م161 — تقرير قيم كل المعامل لشهرٍ مختار (زر «طباعة قيم كل المعامل»).
Future<Uint8List> labsValuesPdf(
  PdfFonts fonts, {
  required String subtitle,
  required String currency,
  required List<LabCard> cards,
}) {
  final c = currency;
  final total = cards.fold<num>(0, (t, k) => t + k.monthValue);
  return _doc(fonts, [
    _h1('قيم المعامل'),
    _sub(subtitle),
    pw.SizedBox(height: 8),
    _table(
      const ['المختبر', 'عدد الحالات', 'قيمة الشهر'],
      [
        for (final k in cards)
          [k.name, '${k.count}', '${_n(k.monthValue)} $c'],
      ],
      totRow: ['الإجمالي', '', '${_n(total)} $c'],
    ),
  ]);
}

/// م161 — تقرير مختبرٍ واحد بجدول م161 (التاريخ/الاسم/العيادة/النوع/
/// الوحدات/القيمة) مرتباً بالأحدث + صف الإجمالي. [byClinic] = قسمٌ لكل
/// عيادة على حدة، وإلا جدولٌ واحد لكل العيادات معاً.
Future<Uint8List> labMonthReportPdf(
  PdfFonts fonts, {
  required String lab,
  required String subtitle,
  required String currency,
  required List<LabRow> rows,
  bool byClinic = false,
}) {
  final c = currency;
  List<List<String>> body(List<LabRow> rs) => [
        for (final r in rs)
          [
            r.date,
            r.name,
            r.clinic.isEmpty ? '—' : r.clinic,
            r.prosType,
            _n(r.units),
            '${_n(r.value)} $c',
          ],
      ];
  List<String> tot(List<LabRow> rs) => [
        'الإجمالي',
        '',
        '',
        '',
        _n(rs.fold<num>(0, (t, r) => t + r.units)),
        '${_n(rs.fold<num>(0, (t, r) => t + r.value))} $c',
      ];
  const headers = [
    'التاريخ', 'الاسم', 'العيادة', 'نوع التركيب', 'الوحدات', 'القيمة',
  ];

  return _doc(fonts, [
    _h1('تقرير مختبر: $lab'),
    _sub(subtitle),
    pw.SizedBox(height: 8),
    if (byClinic)
      for (final e in labRowsByClinic(rows).entries) ...[
        _secTitle(e.key),
        _table(headers, body(e.value), totRow: tot(e.value)),
      ]
    else
      _table(headers, body(rows), totRow: tot(rows)),
  ]);
}

Future<Uint8List> labReportPdf(
  PdfFonts fonts, {
  required String lab,
  required List<LabCase> cases,
  required String currency,
}) {
  final c = currency;
  final collected = labTotalCollected(cases);
  final debt = labTotalDebt(cases);
  final units = labTotalUnits(cases);
  final totalAll = labTotalAll(cases);
  String unitPriceOf(LabCase cs) {
    final stored = jsNumOr0(cs.row['prosUnitPrice']);
    if (stored > 0) return _n(stored);
    final u = jsNumOr0(jsOr(cs.row['prosUnits'], 1));
    final v = jsNumOr0(cs.row['labValue']);
    return u > 0 ? _n(v / u) : '—';
  }

  return _doc(fonts, [
    _h1('تقرير التركيبات — مختبر: $lab'),
    _sub('${cases.length} حالة'),
    pw.SizedBox(height: 8),
    // صناديق الإحصاء العلوية — نفس صناديق المجاميع الرسمية.
    pw.Row(children: [
      _pfTotalBox('عدد الحالات', '${cases.length}', ''),
      _pfTotalBox('إجمالي الوحدات', _n(units), ''),
      _pfTotalBox('إجمالي المخبر', _n(totalAll), c),
    ]),
    _secTitle('حالات التركيبات'),
    pw.SizedBox(height: 4),
    _table(
      ['#', 'المريض', 'التاريخ', 'العيادة', 'النوع', 'الوحدات',
        'سعر الوحدة', 'إجمالي المخبر', 'الحالة'],
      [
        for (var i = 0; i < cases.length; i++)
          [
            '${i + 1}',
            '${cases[i].row['name'] ?? ''}',
            '${cases[i].row['date'] ?? ''}',
            '${cases[i].row['clinic'] ?? ''}',
            '${jsOr(cases[i].row['prosType'], '—')}',
            _n(jsOr(cases[i].row['prosUnits'], 1)),
            unitPriceOf(cases[i]),
            '${_n(cases[i].row['labValue'])} $c',
            cases[i].financialStatus,
          ],
      ],
      totRow: [
        'المجموع', '', '', '', '',
        _n(units), '', '${_n(totalAll)} $c', '',
      ],
    ),
    pw.SizedBox(height: 6),
    _secTitle('الخلاصة المالية'),
    pw.SizedBox(height: 4),
    pw.Row(children: [
      _pfTotalBox('المحصّل', _n(collected), c),
      _pfTotalBox('الديون', _n(debt), c),
      _pfTotalBox('الصافي', _n(collected - debt), c),
    ]),
  ]);
}

// ── تقرير التركيبات — تفصيل الخزينة (v51) ─────────────────────────────────

/// v51 — طباعة التركيبات من تفصيل الخزينة بهوية تقرير الكاش والتحويل:
/// صناديق إحصاء علوية، جدول مجمّع لكل مريض بعنوان نسبته الفعلية
/// (المحسوبة من الحصص المخزنة كلقطات)، أعمدة [التاريخ|البيان|القيمة|
/// المخبر|طبيب|عيادة] وصف مجموع مؤطر بأرقام المجموعة المعروضة في
/// الشاشة نفسها (نفس دوال الحصص حرفياً — صفر انحراف حسابي)، ثم جدول
/// «الإجمالي النهائي» — سهولة تامة في مراجعة الحساب.
Future<Uint8List> prostheticsReportPdf(
  PdfFonts fonts, {
  required String title,
  required String subtitle,
  required String currency,
  required List<ProsGroup> groups,
  required num doctorPct,
}) {
  final c = currency;
  final totalAll = groups.fold<num>(0, (t, g) => t + g.total);
  final labAll = groups.fold<num>(0, (t, g) => t + g.labTotal);
  final docAll = groups.fold<num>(0, (t, g) => t + g.docTotal);
  final clinAll = groups.fold<num>(0, (t, g) => t + g.clinTotal);

  String secOf(ProsGroup g) {
    final profit = g.docTotal + g.clinTotal;
    if (profit <= 0) return g.name;
    final pct = (g.docTotal / profit * 100).round();
    return '${g.name} — نسبة الطبيب الفعلية ~$pct% • العيادة ~${100 - pct}%';
  }

  List<String> rowOf(JMap r) {
    if (r['_t'] == 'p') {
      final isDebt = jsTruthy(r['isDebt']);
      final units = jsNumOr0(jsOr(r['prosUnits'], 1));
      final kind = '${jsOr(r['prosType'], 'تركيبة')}'
          '${units > 1 ? ' × ${_n(units)}' : ''}'
          '${isDebt ? ' (دين)' : ''}';
      return [
        '${r['date'] ?? ''}',
        kind,
        '${_n(r['total'])} $c',
        isDebt ? '—' : '${_n(r['labValue'])} $c',
        isDebt ? '—' : '${_n(r['doctorShare'])} $c',
        isDebt ? '—' : '${_n(r['clinicShare'])} $c',
      ];
    }
    return [
      '${r['date'] ?? ''}',
      'دفعة دين',
      '${_n(r['amount'])} $c',
      '${_n(prosPayLab(r, doctorPct))} $c',
      '${_n(prosPayDoc(r, doctorPct))} $c',
      '${_n(prosPayClin(r, doctorPct))} $c',
    ];
  }

  return _doc(fonts, [
    _h1(title),
    _sub(subtitle),
    pw.SizedBox(height: 8),
    // صناديق الإحصاء العلوية — قراءة فورية لأرقام الشهر.
    pw.Row(children: [
      _pfTotalBox('إجمالي التركيبات', _n(totalAll), c),
      _pfTotalBox('إجمالي المخبر', _n(labAll), c),
      _pfTotalBox('حصة الطبيب', _n(docAll), c),
      _pfTotalBox('حصة العيادة', _n(clinAll), c),
    ]),
    for (final g in groups) ...[
      _secTitle(secOf(g)),
      _table(
        const ['التاريخ', 'البيان', 'القيمة', 'المخبر', 'طبيب', 'عيادة'],
        [for (final r in g.items) rowOf(r)],
        totRow: [
          'المجموع', '',
          '${_n(g.total)} $c',
          '${_n(g.labTotal)} $c',
          '${_n(g.docTotal)} $c',
          '${_n(g.clinTotal)} $c',
        ],
      ),
    ],
    _secTitle('الإجمالي النهائي'),
    _table(
      const ['', 'إجمالي التركيبات', 'المخبر', 'ربح الطبيب', 'ربح العيادة'],
      const [],
      totRow: [
        'المجموع',
        '${_n(totalAll)} $c',
        '${_n(labAll)} $c',
        '${_n(docAll)} $c',
        '${_n(clinAll)} $c',
      ],
    ),
  ]);
}

/// م159 — تقرير التركيبات الجديد: مرآة الجدول الثماني حرفياً من نفس
/// مصدر بيانات الشاشة (prosCaseRows) — كل حالةٍ معالجة مستقلة بقسمها
/// وقيمها، فتتطابق الطباعة مع القائمة رقماً برقم بالبناء.
Future<Uint8List> prosCasesReportPdf(
  PdfFonts fonts, {
  required String title,
  required String subtitle,
  required String currency,
  required List<ProsCaseRow> cases,
  required List<List<JMap>> caseDetails,
  // م180 — الميزة مطفأة ⇒ عمود «الطبيب» يختفي والعيادة = الدفعة − المخبر،
  // وعناوين الحالات بلا نِسَب.
  bool showRates = true,
}) {
  final c = currency;
  num tUnits = 0, tTotal = 0, tPaid = 0, tRem = 0, tLab = 0;
  for (final k in cases) {
    tUnits += k.units;
    tTotal += k.total;
    tPaid += k.paid;
    tRem += k.remaining;
    tLab += k.labShare;
  }

  // م160 — نسبة الطبيب بالمئة في عنوان كل جدول (سلوك التقرير القديم
  // حرفياً): تُحسب الفعلية من قيم دفعات الحالة نفسها (طبيب/الربح).
  String caseTitle(ProsCaseRow k, List<JMap> pays) {
    final doc = pays.fold<num>(0, (t, r) => t + jsNumOr0(r['doc']));
    final clin = pays.fold<num>(0, (t, r) => t + jsNumOr0(r['clin']));
    final profit = doc + clin;
    final base =
        '${k.name} — ${k.work} · ${k.date}${k.isDebtPay ? ' · دفعة دين' : ''}';
    if (!showRates || profit <= 0) return base;
    final pct = (doc / profit * 100).round();
    return '$base — نسبة الطبيب ~$pct% • العيادة ~${100 - pct}%';
  }

  return _doc(fonts, [
    _h1(title),
    _sub(subtitle),
    pw.SizedBox(height: 8),
    // صناديق الإحصاء — نفس أرقام صف إجمالي الجدول في الشاشة.
    pw.Row(children: [
      _pfTotalBox('الإجمالي', _n(tTotal), c),
      _pfTotalBox('المدفوع', _n(tPaid), c),
      _pfTotalBox('المتبقي', _n(tRem), c),
      _pfTotalBox('قيم المعامل', _n(tLab), c),
    ]),
    // ── الجدول الرئيسي — مرآة جدول الشاشة الثماني ──
    _secTitle('جدول الحالات'),
    _table(
      const [
        'التاريخ', 'الاسم', 'المعمل', 'نوع العمل', 'وحدات',
        'الإجمالي', 'المدفوع', 'المتبقي',
      ],
      [
        for (final k in cases)
          [
            k.date,
            '${k.name}${k.isDebtPay ? ' (دفعة دين)' : ''}',
            k.lab.isEmpty ? '—' : k.lab,
            k.work,
            k.units > 0 ? _n(k.units) : '—',
            '${_n(k.total)} $c',
            '${_n(k.paid)} $c',
            '${_n(k.remaining)} $c',
          ],
      ],
      totRow: [
        'الإجمالي',
        'قيم المعامل: ${_n(tLab)} $c',
        '', '',
        tUnits > 0 ? _n(tUnits) : '—',
        '${_n(tTotal)} $c',
        '${_n(tPaid)} $c',
        '${_n(tRem)} $c',
      ],
    ),
    // ── قسمٌ مستقل لكل حالة (لا تجميع بالاسم — م158) ──
    for (var i = 0; i < cases.length; i++) ...[
      _secTitle(caseTitle(cases[i], caseDetails[i])),
      _table(
        [
          'التاريخ', 'الدفعة', 'الدفع', 'المخبر',
          if (showRates) 'الطبيب',
          'العيادة',
        ],
        [
          for (final r in caseDetails[i])
            [
              '${r['date'] ?? ''}',
              '${_n(r['amount'])} $c',
              '${r['payment'] ?? ''}',
              '${_n(r['lab'])} $c',
              if (showRates) '${_n(r['doc'])} $c',
              // م180 — عند الإطفاء: العيادة = حصتها + حصة الطبيب.
              showRates
                  ? '${_n(r['clin'])} $c'
                  : '${_n(jsNumOr0(r['clin']) + jsNumOr0(r['doc']))} $c',
            ],
        ],
        totRow: [
          'المجموع',
          '${_n(caseDetails[i].fold<num>(0, (t, r) => t + jsNumOr0(r['amount'])))} $c',
          '',
          '${_n(caseDetails[i].fold<num>(0, (t, r) => t + jsNumOr0(r['lab'])))} $c',
          if (showRates)
            '${_n(caseDetails[i].fold<num>(0, (t, r) => t + jsNumOr0(r['doc'])))} $c',
          '${_n(caseDetails[i].fold<num>(0, (t, r) => t + jsNumOr0(showRates ? r['clin'] : jsNumOr0(r['clin']) + jsNumOr0(r['doc']))))} $c',
        ],
      ),
    ],
    // ── م160 — الإجمالي النهائي أسفل كل الجداول: كل القيم + نصيبا
    // الطبيب والعيادة عبر كل الحالات (من نفس صفوف التفاصيل المطبوعة).
    _secTitle('الإجمالي النهائي'),
    () {
      num aPay = 0, aLab = 0, aDoc = 0, aClin = 0;
      for (final pays in caseDetails) {
        for (final r in pays) {
          aPay += jsNumOr0(r['amount']);
          aLab += jsNumOr0(r['lab']);
          aDoc += jsNumOr0(r['doc']);
          aClin += jsNumOr0(r['clin']);
        }
      }
      return _table(
        [
          '', 'إجمالي الدفعات', 'المخبر',
          if (showRates) 'نصيب الطبيب',
          'نصيب العيادة',
        ],
        const [],
        totRow: [
          'المجموع',
          '${_n(aPay)} $c',
          '${_n(aLab)} $c',
          if (showRates) '${_n(aDoc)} $c',
          '${_n(showRates ? aClin : aClin + aDoc)} $c',
        ],
      );
    }(),
  ]);
}

// ── تقرير الأسنان ───────────────────────────────────────────────────────────

Future<Uint8List> toothReportPdf(
  PdfFonts fonts, {
  required String clinicName,
  required String date,
  required JMap meta,
  required List<JMap> entries,
  required String currency,
  // م100 — نظام عرض الترقيم (الافتراض Palmer = الرقم المحايد كما كان).
  NotationSystem notation = NotationSystem.palmer,
}) {
  final c = currency;
  final total = entries.fold<num>(0, (s, e) => s + jsNumOr0(e['cost']));
  // م100 — الرمز الصحيح بدل المفتاح الخام `UR:6`، مع قراءة وسم اللبني.
  String teethOf(JMap e) => [
        for (final t in (e['teeth'] as List? ?? const []))
          if (t is Map && jsNumOr0(t['_deleted']) != 1)
            toothLabelFromTooth(t, system: notation).text,
      ].join('، ');
  final conds = (meta['conditions'] as List?)?.join(' • ');

  pw.Widget sig(String label) => pw.Expanded(
        child: pw.Column(children: [
          pw.Container(
              height: 24,
              margin: const pw.EdgeInsets.symmetric(horizontal: 10),
              decoration: const pw.BoxDecoration(
                  border: pw.Border(
                      bottom: pw.BorderSide(color: _mut, width: 1)))),
          pw.SizedBox(height: 4),
          pw.Text(label,
              style: const pw.TextStyle(fontSize: 9, color: _mut)),
        ]),
      );

  pw.Widget info(String label, String v) => pw.Expanded(
        child: pw.Container(
          padding:
              const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: _line)),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(label,
                  style: const pw.TextStyle(fontSize: 8.5, color: _mut)),
              pw.Text(v.isEmpty ? '—' : v,
                  style: pw.TextStyle(
                      fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
            ],
          ),
        ),
      );

  return _doc(fonts, [
    _h1(clinicName),
    _sub('تقرير طب الأسنان — $date'),
    pw.SizedBox(height: 10),
    pw.Row(children: [
      info('الاسم', '${meta['name'] ?? ''}'),
      info('الجوال', '${meta['phone'] ?? ''}'),
      info('العمر', '${meta['age'] ?? ''}'),
    ]),
    pw.SizedBox(height: 10),
    _table(
      ['#', 'الأسنان', 'الخدمة', 'التكلفة'],
      [
        for (var i = 0; i < entries.length; i++)
          [
            '${i + 1}',
            teethOf(entries[i]),
            '${entries[i]['service'] ?? ''}',
            '${_n(entries[i]['cost'])} $c',
          ],
      ],
    ),
    pw.Container(
      margin: const pw.EdgeInsets.only(top: 10),
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _brand900, width: 1.5),
        borderRadius: pw.BorderRadius.circular(5),
      ),
      child: pw.Column(children: [
        pw.Text('إجمالي التكلفة',
            style: const pw.TextStyle(fontSize: 9, color: _mut)),
        pw.Text('${_n(total)} $c',
            style: pw.TextStyle(
                fontSize: 15,
                fontWeight: pw.FontWeight.bold,
                color: _brand900)),
      ]),
    ),
    pw.SizedBox(height: 10),
    pw.Text('التشخيص: ${jsOr(meta['diagnosis'], '—')}',
        style: const pw.TextStyle(fontSize: 10)),
    pw.Text('ملاحظات: ${jsOr(meta['notes'], '—')}',
        style: const pw.TextStyle(fontSize: 10)),
    pw.Text(
        'الأمراض المزمنة: ${(conds == null || conds.isEmpty) ? 'لا يوجد' : conds}',
        style: const pw.TextStyle(fontSize: 10)),
    pw.SizedBox(height: 26),
    pw.Container(
      padding: const pw.EdgeInsets.only(top: 12),
      decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: _line))),
      child: pw.Row(children: [
        sig('توقيع الطبيب'),
        sig('توقيع المريض'),
        sig('ختم المركز'),
      ]),
    ),
  ]);
}

// ── ملف المريض — PrintOverlay حرفياً (م11) ──────────────────────────────────

/// صف بيانات (تسمية فوق قيمة بخط سفلي) — خلايا جدول بيانات المريض.
// م108 — خلية تسمية النموذج: رمادية فاتحة بنص أسود عريض صغير.
pw.Widget _pfFormLabel(String s) => pw.Container(
      color: _hdrBg,
      padding:
          const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3.5),
      child: pw.Text(s,
          style: pw.TextStyle(
              fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
    );

pw.Widget _pfFormValue(String s) => pw.Padding(
      padding:
          const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3.5),
      child: pw.Text(s.isEmpty ? '—' : s,
          style: pw.TextStyle(
              fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
    );

/// جدول نموذجٍ بأربعة أعمدة (تسمية|قيمة|تسمية|قيمة) — عرضا التسمية
/// مثبّتان فيتراصف النموذج كله (والجدول الثنائي أدناه يشاركه العرض).
pw.Widget _pfFormTable4(
        List<(String, String, String, String)> rows) =>
    pw.Table(
      border: pw.TableBorder.all(color: _line, width: .6),
      columnWidths: const {
        // مؤشرات ما بعد عكس RTL: 3=تسمية١ (أقصى اليمين) .. 0=قيمة٢.
        0: pw.FlexColumnWidth(),
        1: pw.FixedColumnWidth(64),
        2: pw.FlexColumnWidth(),
        3: pw.FixedColumnWidth(64),
      },
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: [
        for (final (l1, v1, l2, v2) in rows)
          pw.TableRow(children: [
            _pfFormValue(v2),
            _pfFormLabel(l2),
            _pfFormValue(v1),
            _pfFormLabel(l1),
          ]),
      ],
    );

/// أسطرُ الحقول الطويلة: تسمية بنفس عرض عمود التسمية الأول + قيمة ممتدة.
pw.Widget _pfFormTable2(List<(String, String)> rows) => pw.Table(
      border: const pw.TableBorder(
        left: pw.BorderSide(color: _line, width: .6),
        right: pw.BorderSide(color: _line, width: .6),
        bottom: pw.BorderSide(color: _line, width: .6),
        horizontalInside: pw.BorderSide(color: _line, width: .6),
        verticalInside: pw.BorderSide(color: _line, width: .6),
      ),
      columnWidths: const {
        0: pw.FlexColumnWidth(),
        1: pw.FixedColumnWidth(64),
      },
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: [
        for (final (l, v) in rows)
          pw.TableRow(children: [
            _pfFormValue(v),
            _pfFormLabel(l),
          ]),
      ],
    );

pw.Widget _pfSectionBar(String title) => pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.only(bottom: 3),
      padding: const pw.EdgeInsets.only(bottom: 2),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
            bottom: pw.BorderSide(color: PdfColors.black, width: .9)),
      ),
      child: pw.Text(title,
          style: pw.TextStyle(
              color: PdfColors.black,
              fontSize: 10,
              fontWeight: pw.FontWeight.bold)),
    );

// v50 — صناديق مجاميع مضغوطة (حشوة 8←4 وخط 13←11.5): مساحة أقل
// بوضوح كامل — هدف الورقة الرسمية الواحدة.
pw.Widget _pfTotalBox(String label, String value, String cur) =>
    pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 4),
        decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _ink, width: .8)),
        child: pw.Column(children: [
          pw.Text(label,
              style: pw.TextStyle(
                  fontSize: 9, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 2),
          pw.Text(value,
              style: pw.TextStyle(
                  fontSize: 11.5, fontWeight: pw.FontWeight.bold)),
          if (cur.isNotEmpty)
            pw.Text(cur,
                style: const pw.TextStyle(fontSize: 8, color: _mut)),
        ]),
      ),
    );

/// م107 — خلية مجموعٍ في شريط الليدجر: «تسمية: قيمة عملة» بسطرٍ واحد.
pw.Widget _pfLedgerTotal(String label, String value, String cur) =>
    pw.Expanded(
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text('$label:  ',
              style: const pw.TextStyle(fontSize: 8.5, color: _mut)),
          pw.Text('$value $cur',
              style: pw.TextStyle(
                  fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );

pw.Widget _pfSignature(String label) => pw.Expanded(
      child: pw.Column(children: [
        pw.Container(
            width: 100,
            decoration: const pw.BoxDecoration(
                border: pw.Border(
                    bottom: pw.BorderSide(color: _ink, width: .8)))),
        pw.SizedBox(height: 3),
        pw.Text(label,
            style: pw.TextStyle(
                fontSize: 9, fontWeight: pw.FontWeight.bold)),
      ]),
    );

// v50 — عناصر القسم الطبي: زوج «تسمية: قيمة» وسطرُ نصٍّ ممتد.
/// ملف المريض للطباعة — البنية الحرفية: ترويسة الشعار (شعار الإعدادات أو
/// دائرة سن) + اسم المركز + «تقرير رسمي» + صندوق تاريخ التقرير، جدول
/// بيانات المريض، v50: قسم «المعلومات الطبية» فوق الجدول عند وجودها،
/// جدول سجل الخدمات والمدفوعات (v49: عمود «الأسنان
/// المعالجة» المستقل بعد الخدمة برقاقات مرقمة حسب المحدد، ثم الدفع
/// والمدفوع والدين)، صف المجاميع الثلاثي المؤطر، التواقيع الثلاثة،
/// والتذييل «المركز — التاريخ».
/// م104 — خلية مجموعة أسنانٍ مطبوعة: توأم ToothLabelView في PDF.
/// Palmer: خطا الربع (2×نحافة الطباعة) — العلوي خط أسفل، السفلي خط أعلى،
/// الأيمن خط يمين، الأيسر خط يسار. FDI: صندوق نصي كامل (شكل v49 المألوف).
pw.Widget _pwToothGroupCell(ToothGroupLabel g) {
  const side = pw.BorderSide(color: _brand600, width: 1.1);
  final q = g.quadrant;
  final border = g.palmerBorder
      ? pw.Border(
          bottom: (q == 'UR' || q == 'UL') ? side : pw.BorderSide.none,
          top: (q == 'LR' || q == 'LL') ? side : pw.BorderSide.none,
          right: (q == 'UR' || q == 'LR') ? side : pw.BorderSide.none,
          left: (q == 'UL' || q == 'LL') ? side : pw.BorderSide.none,
        )
      : pw.Border.all(color: _brand600, width: .6);
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 3.5, vertical: 1.5),
    decoration: pw.BoxDecoration(border: border),
    // LTR صريح: المدى «1-8» وسط نص عربي RTL يظل بترتيبه الصحيح.
    child: pw.Directionality(
      textDirection: pw.TextDirection.ltr,
      child: pw.Text(g.text,
          style: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: _brand600)),
    ),
  );
}

/// م105 — شبكة Palmer الصليبية المطبوعة: توأم ToothCrossView في PDF —
/// جدولٌ بحدود داخلية (الوسطي يخترق الصفوف الموجودة فقط، والأفقي بين
/// الفكين أو حداً خارجياً لفكٍّ واحد) — هندسة صور المالك نفسها.
pw.Widget _pwToothCross(ToothCrossModel m) {
  // م106 — مقاسات جدول احترافي: خط 0.8 وخط 7 وحشو رأسي 1 — صفوف مضغوطة
  // موحدة لا تتضخم (الصليب سطران مضغوطان والنصف سطر واحد).
  const side = pw.BorderSide(color: _brand600, width: 0.8);

  pw.Widget cell(String text, {required bool alignEnd}) => pw.Padding(
        padding:
            const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 1),
        child: pw.Align(
          alignment: alignEnd
              ? pw.Alignment.centerRight
              : pw.Alignment.centerLeft,
          child: pw.Directionality(
            textDirection: pw.TextDirection.ltr,
            child: pw.Text(text,
                style: pw.TextStyle(
                    fontSize: 7,
                    fontWeight: pw.FontWeight.bold,
                    color: _brand600)),
          ),
        ),
      );

  final both = m.hasUpper && m.hasLower;
  return pw.Table(
    // م108 — نصفان بعرضين ثابتين متساويين: الخط الوسطي يقع في الموضع
    // نفسه بكل صفوف الجدول فتتراصف الشبكات تحت بعضها عمودياً.
    columnWidths: const {
      0: pw.FixedColumnWidth(34),
      1: pw.FixedColumnWidth(34),
    },
    defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
    border: pw.TableBorder(
      verticalInside: side,
      horizontalInside: both ? side : pw.BorderSide.none,
      bottom: m.hasUpper && !m.hasLower ? side : pw.BorderSide.none,
      top: m.hasLower && !m.hasUpper ? side : pw.BorderSide.none,
    ),
    children: [
      if (m.hasUpper)
        pw.TableRow(children: [
          cell(m.upperRight, alignEnd: true),
          cell(m.upperLeft, alignEnd: false),
        ]),
      if (m.hasLower)
        pw.TableRow(children: [
          cell(m.lowerRight, alignEnd: true),
          cell(m.lowerLeft, alignEnd: false),
        ]),
    ],
  );
}

Future<Uint8List> patientFilePdf(
  PdfFonts fonts, {
  required String centerName,
  required String patientName,
  required String phone,
  required int visitCount,
  required String currency,
  required String reportDate,
  required List<
          ({
        String date,
        String service,
        // م104 — مجموعات ملخصة (مدى ربعي) بدل نصوص مفردة: تُرسم خلايا
        // Palmer حقيقية بحدود الربع في الورقة (وFDI صندوقاً نصياً كاملاً).
        List<ToothGroupLabel> teeth,
        // م105 — عند تعدد الأرباع: نموذج الشبكة الصليبية يتقدم على
        // المجموعات (null = ربع واحد ⇒ خلايا القوس أعلاه).
        ToothCrossModel? cross,
        String payment,
        num paid,
        num debt,
      })>
      rows,
  required num totalServices,
  required num totalPaid,
  required num totalRemaining,
  // v50 — المعلومات الطبية المحفوظة للمريض (gender/age/conditions/
  // diagnosis/notes) — قسم احترافي فوق جدول المعالجات عند وجودها.
  JMap? medical,
}) {
  final doc = pw.Document(theme: fonts.theme());
  final logo = pdfLogoBytes;

  // v50 — تجهيز حقول القسم الطبي (يظهر فقط عند وجود أي بيانات).
  final med = medical ?? const <String, Object?>{};
  final medGender = '${med['gender'] ?? ''}'.trim();
  final medAge = '${med['age'] ?? ''}'.trim();
  final medConds = [
    for (final c in (med['conditions'] as List? ?? const [])) '$c',
  ];
  String medJoin(Object? v) => '$v'
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .join(' • ');
  final medDiag = medJoin(med['diagnosis'] ?? '');
  final medNotes = medJoin(med['notes'] ?? '');
  final hasMedical = medGender.isNotEmpty ||
      medAge.isNotEmpty ||
      medConds.isNotEmpty ||
      medDiag.isNotEmpty ||
      medNotes.isNotEmpty;

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    // م107 — هوامش 22←18: أقل ورق ممكن.
    margin: const pw.EdgeInsets.all(18),
    textDirection: pw.TextDirection.rtl,
    build: (ctx) => [
      // ── م107: ترويسة سطر واحد — شعار صغير + اسم المركز + «ملف
      // مريض • التاريخ» (مرة واحدة — كان مكرراً مرتين)، ثم خط أسود.
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          if (logo != null) ...[
            pw.Container(
              width: 34,
              height: 34,
              decoration: pw.BoxDecoration(
                shape: pw.BoxShape.circle,
                border: pw.Border.all(color: _ink, width: .9),
              ),
              alignment: pw.Alignment.center,
              child: pw.ClipOval(
                  child: pw.Image(pw.MemoryImage(logo),
                      width: 32, height: 32, fit: pw.BoxFit.cover)),
            ),
            pw.SizedBox(width: 8),
          ],
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(centerName,
                    style: pw.TextStyle(
                        fontSize: 13, fontWeight: pw.FontWeight.bold)),
                pw.Text('ملف مريض • $reportDate',
                    style:
                        const pw.TextStyle(fontSize: 8.5, color: _mut)),
              ],
            ),
          ),
        ],
      ),
      pw.Container(
          height: 1.4,
          color: PdfColors.black,
          margin: const pw.EdgeInsets.only(top: 5, bottom: 6)),

      // ── م108: بيانات المريض والمعلومات الطبية في جدول نموذجٍ
      // متناظرٍ واحد (تسمية رمادية فاتحة | قيمة) — «تناظر ومريح للعين».
      // الحقول القصيرة أزواجاً بأربعة أعمدة، والطويلة (الحالات/التشخيص/
      // الملاحظات) أسطرُ تسمية|قيمة بنفس عرض عمود التسمية فيبدو الكل
      // جدولاً واحداً موحّد الرصف. ──
      // م109 — حُذف صف «عدد الزيارات/العملة» (طلب المالك): المعلومة
      // تبقى في النظام، والعملة ظاهرة في شريط المجاميع بجانب الأرقام.
      _pfFormTable4([
        ('الاسم الكامل', patientName, 'رقم الجوال', phone),
        if (medGender.isNotEmpty || medAge.isNotEmpty)
          ('الجنس', medGender.isEmpty ? '—' : medGender, 'العمر',
              medAge.isEmpty ? '—' : medAge),
      ]),
      if (hasMedical)
        _pfFormTable2([
          // م109 — التسمية الموحدة الجديدة (توأم حوار المعلومات الطبية).
          if (medConds.isNotEmpty) ('الأمراض العامة', medConds.join('، ')),
          if (medDiag.isNotEmpty) ('التشخيص', medDiag),
          if (medNotes.isNotEmpty) ('ملاحظات', medNotes),
        ]),
      pw.SizedBox(height: 6),

      // ── سجل الخدمات والمدفوعات ──
      _pfSectionBar('سجل الخدمات والمدفوعات'),
      pw.Table(
        border: pw.TableBorder.all(color: _line, width: .6),
        // م27 — أعمدة معكوسة لعرض RTL (pw.Table لا يدعم الاتجاه): العرض
        // مُعاد التخطيط new[i]=old[6-i] فيبقى عمود «#» الضيق أقصى اليمين
        // مع خلاياه، و«الاسم/الخدمة» تُقرأ يميناً كجدول Vue.
        // v49 — عمود «الأسنان المعالجة» المستقل بعد الخدمة (طلب المالك):
        // الرقاقات التي كانت تحت اسم الخدمة انتقلت إليه.
        columnWidths: {
          0: const pw.FlexColumnWidth(1.0), // الدين
          1: const pw.FlexColumnWidth(1.2), // المدفوع
          2: const pw.FlexColumnWidth(1.0), // الدفع
          3: const pw.FlexColumnWidth(1.8), // الأسنان المعالجة
          4: const pw.FlexColumnWidth(2.0), // الخدمة
          5: const pw.FlexColumnWidth(1.4), // التاريخ
          6: const pw.FixedColumnWidth(22), // #
        },
        defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
        children: [
          // م107 — رأس ليدجر: فاتح بنص أسود بين خطين.
          pw.TableRow(
            decoration: const pw.BoxDecoration(
              color: _hdrBg,
              border: pw.Border(
                  top: pw.BorderSide(
                      color: PdfColors.black, width: .9),
                  bottom: pw.BorderSide(
                      color: PdfColors.black, width: .9)),
            ),
            children: [
              for (final h in ['#', 'التاريخ', 'الخدمة',
                'الأسنان المعالجة', 'الدفع', 'المدفوع', 'الدين'])
                _cell(h, bold: true, color: PdfColors.black),
            ].reversed.toList(),
          ),
          for (var i = 0; i < rows.length; i++)
            pw.TableRow(children: [
              _cell('${i + 1}'),
              _cell(rows[i].date),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(
                    horizontal: 6, vertical: 4),
                child: pw.Text(rows[i].service,
                    style: pw.TextStyle(
                        fontSize: 9.5,
                        fontWeight: pw.FontWeight.bold)),
              ),
              // م104/م105 — خلية الأسنان: شبكة صليبية عند تعدد الأرباع،
              // وإلا مجموعات القوس الربعية، و«—» لصف بلا أسنان.
              rows[i].cross != null
                  ? pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(
                          horizontal: 5, vertical: 2),
                      // م106 — بلا FittedBox: كان يتمدد لملء عرض العمود
                      // فيتضخم ارتفاع الصف عشوائياً حسب المحتوى؛ الشبكة
                      // بحجمها الطبيعي المضغوط وسط الخلية = صفوف موحدة.
                      child: pw.Center(
                          child: _pwToothCross(rows[i].cross!)),
                    )
                  : rows[i].teeth.isEmpty
                      ? _cell('—', color: _mut)
                      : pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(
                              horizontal: 5, vertical: 3),
                          child: pw.Wrap(
                            spacing: 3,
                            runSpacing: 3,
                            children: [
                              for (final g in rows[i].teeth)
                                _pwToothGroupCell(g),
                            ],
                          ),
                        ),
              _cell(rows[i].payment),
              _cell(_n(rows[i].paid), bold: true),
              _cell(rows[i].debt > 0 ? _n(rows[i].debt) : '—'),
            ].reversed.toList()),
        ],
      ),
      pw.SizedBox(height: 6),

      // ── م107: المجاميع شريطُ ليدجرٍ واحد بخطٍّ علوي أسود (بدل
      // ثلاثة صناديق كبيرة). ──
      pw.Container(
        decoration: const pw.BoxDecoration(
          color: PdfColor.fromInt(0xFFF2F2F2),
          border: pw.Border(
              top: pw.BorderSide(color: PdfColors.black, width: 1.2),
              bottom: pw.BorderSide(color: _line, width: .6)),
        ),
        padding: const pw.EdgeInsets.symmetric(vertical: 5),
        child: pw.Row(children: [
          _pfLedgerTotal('إجمالي الخدمات', _n(totalServices), currency),
          _pfLedgerTotal('المدفوع فعلياً', _n(totalPaid), currency),
          _pfLedgerTotal('الرصيد المتبقي', _n(totalRemaining), currency),
        ]),
      ),
      pw.SizedBox(height: 10),

      // ── التواقيع ──
      pw.Row(children: [
        _pfSignature('توقيع الطبيب'),
        _pfSignature('توقيع المريض'),
        _pfSignature('ختم المركز'),
      ]),
      pw.SizedBox(height: 6),
      pw.Divider(color: _line, thickness: .6),
      pw.Center(
        child: pw.Text('$centerName — $reportDate',
            style: const pw.TextStyle(fontSize: 7.5, color: _mut)),
      ),
    ],
  ));
  return doc.save();
}

/// م120 — تقرير تسليم الوردية (Z-Report): مقبوضات موظفٍ واحدٍ اليوم
/// (كاش/تحويل/دين)، مصروفاته، ورصيد تسليم الدرج — يطبعه نهاية دوامه
/// وتقارنه الإدارة بما يسلَّم فعلاً. البنية توأم تقرير قفل اليوم
/// (م106) كي يألفها المالك، مع ترويسة الموظف وسطر التسليم الختامي.
Future<Uint8List> shiftReportPdf(
  PdfFonts fonts, {
  required String date,
  required String staffName,
  required String printedAt,
  required String centerName,
  required String currency,
  required List<List<String>> incomeRows,
  required String totalPaid,
  required String cashPaid,
  required String transferPaid,
  required String debtRemaining,
  required List<List<String>> expenseRows,
  required String expenseTotal,
  required String expenseCash,
  required String expenseTransfer,
  required String drawerCash,
  required String drawerTransfer,
  String unattributedNote = '',
}) {
  pw.Widget h2(String t) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 12, bottom: 4),
        child: pw.Text(t,
            style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.black)),
      );
  pw.Widget totals(List<String> headers, List<String> values) =>
      _table(headers, const [], totRow: values);

  return _doc(fonts, [
    pw.Center(
        child: pw.Text('تقرير تسليم وردية — $date',
            style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.black))),
    pw.SizedBox(height: 2),
    _sub('الموظف: $staffName'),
    if (centerName.isNotEmpty) _sub(centerName),
    _sub('طُبع: $printedAt'),
    pw.SizedBox(height: 10),
    h2('أولاً — مقبوضات الوردية'),
    if (incomeRows.isEmpty)
      _sub('لا مقبوضات مسجَّلة لهذا الموظف اليوم')
    else
      _table(const [
        '#', 'الساعة', 'الاسم', 'العيادة', 'الدفع',
        'القيمة', 'المدفوع', 'المتبقي',
      ], incomeRows),
    pw.SizedBox(height: 5),
    totals(
      ['الإجمالي (المقبوض) $currency', 'كاش', 'تحويل', 'الدين المتبقي'],
      [totalPaid, cashPaid, transferPaid, debtRemaining],
    ),
    h2('ثانياً — مصروفات الوردية'),
    if (expenseRows.isEmpty)
      _sub('لا مصروفات مسجَّلة لهذا الموظف اليوم')
    else
      _table(const ['#', 'الساعة', 'البند', 'الفئة', 'الدفع', 'المبلغ'],
          expenseRows),
    pw.SizedBox(height: 5),
    totals(
      ['إجمالي المصروف', 'مصروف كاش', 'مصروف تحويل'],
      [expenseTotal, expenseCash, expenseTransfer],
    ),
    h2('ثالثاً — رصيد تسليم الدرج (المقبوض − المصروف)'),
    totals(
      ['كاش يُسلَّم $currency', 'تحويل (للمطابقة)'],
      [drawerCash, drawerTransfer],
    ),
    if (unattributedNote.isNotEmpty) ...[
      pw.SizedBox(height: 8),
      _sub(unattributedNote),
    ],
    pw.SizedBox(height: 14),
    pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
      pw.Text('توقيع الموظف: ______________',
          style: const pw.TextStyle(fontSize: 10)),
      pw.Text('توقيع الإدارة: ______________',
          style: const pw.TextStyle(fontSize: 10)),
    ]),
  ]);
}
