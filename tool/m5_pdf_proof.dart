/// إثبات م5 — توليد التقارير الثلاثة الفعلية (شهر/مختبر/أسنان) بخط القاهرة
/// إلى ملفات PDF للمعاينة البصرية.  التشغيل: dart run tool/m5_pdf_proof.dart
library;

import 'dart:io';

import 'package:dental_clinic_flutter/features/archive/month_stats.dart';
import 'package:dental_clinic_flutter/features/labs/labs_logic.dart';
import 'package:dental_clinic_flutter/features/print/reports.dart';
import 'package:dental_clinic_flutter/features/print/treatment_tables.dart';

Future<void> main() async {
  final fonts = PdfFonts(
    regular: File('assets/fonts/Cairo-Regular.ttf')
        .readAsBytesSync()
        .buffer
        .asByteData(),
    bold: File('assets/fonts/Cairo-Bold.ttf')
        .readAsBytesSync()
        .buffer
        .asByteData(),
  );

  final monthly = await monthlyReportPdf(
    fonts,
    month: '2026-06',
    centerName: 'مركز الابتسامة لطب الأسنان',
    currency: 'د.ل',
    data: const MonthData(
        inMem: true,
        cash: 1450,
        xfer: 600,
        prosDoc: 390,
        prosTotal: 1800,
        total: 3850),
    recTables: buildTreatmentTables([
      {
        'name': 'أحمد الطيّب', 'date': '2026-06-03', 'amount': 250,
        'payment': 'كاش', 'service': 'حشو ضوئي',
        '_rateSnapshot': {'doctorPct': 40},
      },
      {
        'name': 'سعاد المبروك', 'date': '2026-06-05', 'amount': 400,
        'payment': 'تحويل', 'service': 'حشو ضوئي',
        '_rateSnapshot': {'doctorPct': 40},
      },
      {
        'name': 'خالد إبراهيم', 'date': '2026-06-11', 'amount': 800,
        'payment': 'كاش', 'service': 'حشو عصب',
        '_rateSnapshot': {'doctorPct': 45},
      },
      {
        'name': 'هدى عمران', 'date': '2026-06-14', 'amount': 120,
        'payment': 'كاش', 'service': 'أشعة بانورامية',
        '_rateSnapshot': {'doctorPct': 0},
      },
    ]),
    prosRows: [
      {
        'name': 'مريم الصادق', 'date': '2026-06-09', 'total': 1200,
        'labValue': 450, 'doctorShare': 225, 'clinicShare': 525,
      },
      {
        'name': 'نوري بلعيد', 'date': '2026-06-20', 'total': 600,
        'labValue': 200, 'doctorShare': 120, 'clinicShare': 280,
      },
    ],
    pendingDebts: [
      {'remaining': 350},
      {'remaining': 900},
    ],
  );
  File('../m5_monthly_report.pdf').writeAsBytesSync(monthly);

  final lab = await labReportPdf(
    fonts,
    lab: 'مخبر النور للتركيبات',
    currency: 'د.ل',
    cases: labCases('مخبر النور للتركيبات', prosthetics: [
      {
        'id': 'p1', 'labName': 'مخبر النور للتركيبات', 'labValue': 450,
        'date': '2026-06-09', 'clinic': 'العيادة الأولى',
        'name': 'مريم الصادق', 'prosType': 'زيركون', 'prosUnits': 3,
      },
      {
        'id': 'p2', 'labName': 'مخبر النور للتركيبات', 'labValue': 200,
        'date': '2026-06-20', 'clinic': 'العيادة الأولى',
        'name': 'نوري بلعيد', 'prosType': 'طقم جزئي', 'isDebt': true,
      },
    ], debts: [
      {
        'id': 'd2', 'prostheticId': 'p2', 'status': 'partial',
        'remaining': 300, 'labPaid': 50, 'date': '2026-06-20',
      },
    ], records: const []),
  );
  File('../m5_lab_report.pdf').writeAsBytesSync(lab);

  final tooth = await toothReportPdf(
    fonts,
    clinicName: 'مركز الابتسامة لطب الأسنان',
    date: '2026-07-26',
    currency: 'د.ل',
    meta: {
      'name': 'هدى عمران',
      'phone': '0911111111',
      'age': '34',
      'diagnosis': 'تسوس متقدم في الرحى الأولى السفلية اليسرى',
      'notes': 'مراجعة بعد أسبوعين لاستكمال علاج العصب',
      'conditions': ['السكري', 'حساسية الأدوية'],
    },
    entries: [
      {
        'teeth': [
          {'q': 'LL', 'n': 6},
        ],
        'service': 'حشو عصب',
        'cost': 800,
      },
      {
        'teeth': [
          {'q': 'UR', 'n': 1},
          {'q': 'UL', 'n': 1},
        ],
        'service': 'تبييض',
        'cost': 350,
      },
    ],
  );
  File('../m5_tooth_report.pdf').writeAsBytesSync(tooth);

  stdout.writeln('m5 PDFs written: monthly=${monthly.length}b '
      'lab=${lab.length}b tooth=${tooth.length}b');
}
