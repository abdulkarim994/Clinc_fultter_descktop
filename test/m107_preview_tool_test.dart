/// أداة معاينة م107 (مؤقتة) — تبني ملف مريضٍ وكشفَ عيادةٍ بالتصميم
/// المحاسبي الأحادي الجديد ببيانات تطابق لقطات المالك، وتكتب PDF إلى
/// build/m107_preview/ ليحوَّل صوراً تُعرض عليه قبل بناء APK.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/features/print/reports.dart';
import 'package:dental_clinic_flutter/features/print/treatment_tables.dart';
import 'package:dental_clinic_flutter/features/records/tooth_summary.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('م107 معاينة — توليد PDF بالتصميم الجديد', () async {
    final fonts = PdfFonts(
      regular: await rootBundle.load('assets/fonts/Cairo-Regular.ttf'),
      bold: await rootBundle.load('assets/fonts/Cairo-Bold.ttf'),
      fallback: await rootBundle.load('assets/fonts/Qomra-Regular.ttf'),
    );
    final dir = Directory('build/m107_preview')..createSync(recursive: true);

    // ── 1) ملف المريض — نفس بيانات لقطة المالك تقريباً ──
    final patient = await patientFilePdf(
      fonts,
      centerName: 'عبدالكريم',
      patientName: 'محمد علي',
      phone: '096559',
      visitCount: 6,
      currency: 'د.ل',
      reportDate: '2026-08-02',
      rows: [
        (
          date: '2026-08-01',
          service: 'حشو عصب',
          teeth: const <ToothGroupLabel>[],
          cross: const ToothCrossModel(
              upperRight: '53', upperLeft: '', lowerRight: '83',
              lowerLeft: ''),
          payment: 'دين',
          paid: 500,
          debt: 0,
        ),
        (
          date: '2026-08-01',
          service: 'حشو عصب',
          teeth: const <ToothGroupLabel>[],
          cross: const ToothCrossModel(
              upperRight: '55,54', upperLeft: '61,63-65',
              lowerRight: '84,82', lowerLeft: '71,73-75'),
          payment: 'دين',
          paid: 300,
          debt: 0,
        ),
        (
          date: '2026-08-02',
          service: 'خلع',
          teeth: const <ToothGroupLabel>[],
          cross: const ToothCrossModel(
              upperRight: '54-52', upperLeft: '64', lowerRight: '',
              lowerLeft: ''),
          payment: 'دين',
          paid: 2500,
          debt: 0,
        ),
        (
          date: '2026-08-02',
          service: 'تقويم',
          teeth: const <ToothGroupLabel>[],
          cross: const ToothCrossModel(
              upperRight: '55', upperLeft: '65', lowerRight: '85',
              lowerLeft: '75'),
          payment: 'دين',
          paid: 500,
          debt: 4500,
        ),
        (
          date: '2026-08-02',
          service: 'تقويم',
          teeth: const <ToothGroupLabel>[],
          cross: const ToothCrossModel(
              upperRight: '18-11', upperLeft: '21-28',
              lowerRight: '48-41', lowerLeft: '31-38'),
          payment: 'تحويل',
          paid: 500,
          debt: 0,
        ),
      ],
      totalServices: 9180,
      totalPaid: 4680,
      totalRemaining: 4500,
      medical: {
        'gender': 'ذكر',
        'age': '30',
        'conditions': ['ضغط الدم', 'أمراض الكلى', 'حمل'],
        'diagnosis': 'لديه امراض عامة',
        'notes': 'انتظر',
      },
    );
    File('${dir.path}/patient.pdf').writeAsBytesSync(patient);

    // ── 2) كشف العيادة (جداول المعالجات) — كما في لقطته الثانية ──
    final tables = await treatmentTablesPdf(
      fonts,
      title: 'الصفوة — تحويل',
      subtitle: '2026-08',
      currency: 'د.ل',
      // م108 — عبر البانية الحقيقية: دفعات الدين تُدمج في جدول معالجتها.
      tables: buildTreatmentTables([
        {
          'name': 'حسين محمد علي', 'date': '2026-08-01',
          'service': 'تقويم', 'amount': 280, 'payment': 'تحويل',
          '_rateSnapshot': {'doctorPct': 50},
        },
        {
          'name': 'علي حسين', 'date': '2026-08-02',
          'service': 'تقويم', 'amount': 1500, 'payment': 'تحويل',
          '_rateSnapshot': {'doctorPct': 50},
        },
        {
          'name': 'foffl', 'date': '2026-08-01',
          'service': 'حشو عصب', 'amount': 550, 'payment': 'تحويل',
          '_rateSnapshot': {'doctorPct': 30},
        },
        {
          'name': 'محمد علي', 'date': '2026-08-01',
          'service': 'دفعة دين — حشو عصب', 'amount': 400,
          'payment': 'تحويل',
          '_rateSnapshot': {'doctorPct': 30, 'treatmentId': 'حشو عصب'},
        },
      ]),
    );
    File('${dir.path}/tables.pdf').writeAsBytesSync(tables);

    expect(patient.length, greaterThan(1000));
    expect(tables.length, greaterThan(1000));
  });
}
