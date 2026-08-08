/// أداة إثبات PDF العربي — الميلستون صفر.
///
/// تولّد نموذج تقرير عيادة حقيقي (ترويسة، بيانات مريض بالتشكيل، جدول سجلات،
/// سطر إجهاد لوصل الحروف واللامات) بخط قمرة عبر حزمة dart pdf، للتحقق من أن
/// محرك تشكيل النصوص يخرج العربية سليمة قبل اعتماد المسار في م5.
///
/// التشغيل:  dart run tool/pdf_proof.dart
library;

import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

const _brand900 = PdfColor.fromInt(0xFF0A3024);
const _brand600 = PdfColor.fromInt(0xFF15604A);
const _gold = PdfColor.fromInt(0xFFC9A24B);
const _paper = PdfColor.fromInt(0xFFF6F2E8);
const _ink = PdfColor.fromInt(0xFF0F2A20);

pw.Font _ttf(String path) =>
    pw.Font.ttf(File(path).readAsBytesSync().buffer.asByteData());

Future<void> main() async {
  final baseFont = Platform.environment["PDF_BASE"] ?? "Qomra";
  final qomra = _ttf(baseFont == "Cairo" ? "assets/fonts/Cairo-Regular.ttf" : "assets/fonts/Qomra-Regular.ttf");
  final qomraBold = _ttf(baseFont == "Cairo" ? "assets/fonts/Cairo-Bold.ttf" : "assets/fonts/Qomra-Bold.ttf");
  final cairo = _ttf("assets/fonts/Cairo-Regular.ttf");

  final doc = pw.Document(
    theme: pw.ThemeData.withFont(
      base: qomra,
      bold: qomraBold,
      fontFallback: [cairo],
    ),
  );

  pw.Widget cell(String s, {bool bold = false, PdfColor? color}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: pw.Text(
          s,
          style: pw.TextStyle(
            fontSize: 11,
            color: color ?? _ink,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      );

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      build: (ctx) => pw.Directionality(
        textDirection: pw.TextDirection.rtl,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            // ── Header ──
            pw.Container(
              padding: const pw.EdgeInsets.all(18),
              decoration: pw.BoxDecoration(
                color: _brand900,
                borderRadius: pw.BorderRadius.circular(12),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('طب الأسنان الرقمي',
                          style: pw.TextStyle(
                              color: PdfColors.white,
                              fontSize: 20,
                              fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 4),
                      pw.Text('تقرير مالي — إثبات توليد PDF عربي (م0)',
                          style: const pw.TextStyle(
                              color: _gold, fontSize: 11)),
                    ],
                  ),
                  pw.Text('السبت 26 يوليو 2026',
                      style: pw.TextStyle(
                          color: PdfColors.white.shade(.15), fontSize: 11)),
                ],
              ),
            ),
            pw.SizedBox(height: 16),

            // ── Patient block (tashkeel + hamza traps) ──
            pw.Container(
              padding: const pw.EdgeInsets.all(14),
              decoration: pw.BoxDecoration(
                color: _paper,
                borderRadius: pw.BorderRadius.circular(10),
                border: pw.Border.all(color: _gold, width: .8),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('بيانات المريض',
                      style: pw.TextStyle(
                          fontSize: 13,
                          fontWeight: pw.FontWeight.bold,
                          color: _brand600)),
                  pw.SizedBox(height: 6),
                  pw.Text(
                      'الاسم: مُحَمَّد عَبْدُ الرَّحْمٰن الشَّريف   ·   الهاتف: 0912345678',
                      style: const pw.TextStyle(fontSize: 11.5)),
                  pw.Text(
                      'حالات اختبار الهمزات: أحمد، إبراهيم، آمنة، مُؤمِن، هيئة، عيادة الزهراء',
                      style: const pw.TextStyle(fontSize: 11.5)),
                ],
              ),
            ),
            pw.SizedBox(height: 16),

            // ── Records table (RTL, mixed digits) ──
            pw.Table(
              border: pw.TableBorder.all(color: _brand600, width: .4),
              columnWidths: {
                0: const pw.FlexColumnWidth(2.2),
                1: const pw.FlexColumnWidth(1.4),
                2: const pw.FlexColumnWidth(1.2),
                3: const pw.FlexColumnWidth(1.2),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: _brand600),
                  children: [
                    cell('الخدمة العلاجية',
                        bold: true, color: PdfColors.white),
                    cell('التاريخ', bold: true, color: PdfColors.white),
                    cell('المبلغ (د.ل)', bold: true, color: PdfColors.white),
                    cell('الحالة', bold: true, color: PdfColors.white),
                  ],
                ),
                pw.TableRow(children: [
                  cell('حشو ضوئي — السن 36'),
                  cell('2026/07/12'),
                  cell('250.00'),
                  cell('مدفوع'),
                ]),
                pw.TableRow(children: [
                  cell('علاج عصب مع تلبيسة زيركون'),
                  cell('2026/07/19'),
                  cell('1,250.50'),
                  cell('قسط أول'),
                ]),
                pw.TableRow(children: [
                  cell('تنظيف الجير وتلميع'),
                  cell('2026/07/26'),
                  cell('80.00'),
                  cell('دين'),
                ]),
              ],
            ),
            pw.SizedBox(height: 16),

            // ── Ligature stress line ──
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _brand600, width: .6),
                borderRadius: pw.BorderRadius.circular(10),
              ),
              child: pw.Text(
                'إجهاد الوصل واللامات: لا، لأ، لآ، الله، فحص، تجميل، مستشفى — '
                'وأرقام مختلطة: الفاتورة رقم 1580 بتاريخ 2026/07/26 بمبلغ 1,580.50 د.ل',
                style: const pw.TextStyle(fontSize: 11.5, lineSpacing: 3),
              ),
            ),
            pw.Spacer(),

            // ── Footer ──
            pw.Container(
              alignment: pw.Alignment.center,
              padding: const pw.EdgeInsets.only(top: 10),
              decoration: const pw.BoxDecoration(
                border: pw.Border(top: pw.BorderSide(color: _gold, width: 1)),
              ),
              child: pw.Text(
                'وُلّد بواسطة dart pdf — خط قمرة (المحوّل من woff) + Cairo احتياطياً',
                style: pw.TextStyle(fontSize: 9.5, color: _ink.shade(.3)),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  final bytes = await doc.save();
  File('/tmp/pdf_proof.pdf').writeAsBytesSync(bytes);
  // ignore: avoid_print
  print('PDF_OK ${bytes.length} bytes -> /tmp/pdf_proof.pdf');
}
