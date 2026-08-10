/// م153 — قاعدة تكرار التحليل بنطاق العيادة + استثناء السميَّين (قرارا
/// المالك 2026-08-10).
///
/// (أ) نطاق العيادة: «محمد أحمد» في عيادتين حرٌّ في كلٍّ منهما على حدة —
///     المطابقة داخل نفس العيادة فقط (clinic ثم clinic_id احتياطاً)،
///     والفارغة = بلا قصر (سلوك احتياطي).
/// (ب) استثناء السميَّين: هاتفان **صريحان مختلفان** على الطرفين = شخصان
///     فيُسمح؛ غياب هاتف أي طرفٍ = غموض ⇒ يبقى الحجب احتياطاً؛ وتطابق
///     المعرّفين = نفس المريض حتماً مهما كانت الهواتف.
/// (ج) الكاتبان: نفس الاسم بعيادةٍ أخرى يمرّ عبر addAnalysisToVisit
///     وsaveNewRecord — وبنفس العيادة يُصَدّ.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/core/utils/ar_normalize.dart'
    show arNorm;
import 'package:dental_clinic_flutter/core/utils/js_compat.dart'
    show getCurrentDate, jsTruthy;
import 'package:dental_clinic_flutter/features/records/record_saver.dart';
import 'package:dental_clinic_flutter/features/settings/analyses3.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'staff_test_session.dart' show staffAdminSession;

typedef JMap = Map<String, Object?>;

void main() {
  final today = getCurrentDate();

  JMap triRow({
    required String id,
    required String name,
    String? patientId,
    String clinic = 'الصفوة',
    String? date,
  }) => {
        'id': id,
        'isAnalysis': 1,
        'analysisName': kTriAnalysesName,
        'name': name,
        'patient_name': name,
        'patient_id': ?patientId,
        'clinic': clinic,
        'clinic_id': clinic,
        'amount': 50,
        'payment': 'كاش',
        'date': date ?? today,
      };

  group('م153/أ — نطاق العيادة', () {
    final rows = [triRow(id: 'a1', name: 'محمد أحمد', clinic: 'الصفوة')];

    test('نفس الاسم بعيادةٍ أخرى = حرٌّ (لا حجب)', () {
      expect(
        lastTriAnalysisDate(rows,
            patientName: 'محمد أحمد', clinic: 'كاريزما', normalize: arNorm),
        isNull,
      );
    });

    test('نفس الاسم بنفس العيادة = محجوب', () {
      expect(
        lastTriAnalysisDate(rows,
            patientName: 'محمد أحمد', clinic: 'الصفوة', normalize: arNorm),
        today,
      );
    });

    test('عيادة فارغة (احتياط) = بلا قصر — يطابق عبر العيادات', () {
      expect(
        lastTriAnalysisDate(rows,
            patientName: 'محمد أحمد', normalize: arNorm),
        today,
      );
    });

    test('صف قديم بلا clinic يُطابَق بـ clinic_id احتياطاً', () {
      final legacy = [
        {
          'id': 'a2',
          'isAnalysis': 1,
          'analysisName': kTriAnalysesName,
          'patient_name': 'سالم',
          'clinic_id': 'النخبة',
          'amount': 50,
          'payment': 'كاش',
          'date': today,
        },
      ];
      expect(
        lastTriAnalysisDate(legacy,
            patientName: 'سالم', clinic: 'النخبة', normalize: arNorm),
        today,
      );
      expect(
        lastTriAnalysisDate(legacy,
            patientName: 'سالم', clinic: 'الصفوة', normalize: arNorm),
        isNull,
      );
    });
  });

  group('م153/ب — استثناء السميَّين بهاتفين صريحين', () {
    test('هاتفان صريحان مختلفان (من المعرّفين) = شخصان ⇒ يمرّ', () {
      final rows =
          [triRow(id: 'a1', name: 'محمد أحمد', patientId: 'p:0911:محمد احمد')];
      expect(
        lastTriAnalysisDate(rows,
            patientId: 'p:0922:محمد احمد',
            patientName: 'محمد أحمد',
            clinic: 'الصفوة',
            normalize: arNorm),
        isNull,
      );
    });

    test('الهاتف الصريح من معامل [phone] يعمل كالمعرّف', () {
      final rows =
          [triRow(id: 'a1', name: 'محمد أحمد', patientId: 'p:0911:محمد احمد')];
      expect(
        lastTriAnalysisDate(rows,
            patientName: 'محمد أحمد',
            phone: '0922',
            clinic: 'الصفوة',
            normalize: arNorm),
        isNull,
      );
      // ونفس الهاتف = نفس الشخص ⇒ محجوب.
      expect(
        lastTriAnalysisDate(rows,
            patientName: 'محمد أحمد',
            phone: '0911',
            clinic: 'الصفوة',
            normalize: arNorm),
        today,
      );
    });

    test('غياب هاتف أحد الطرفين = غموض ⇒ يبقى الحجب', () {
      // صف بلا هاتف (معرّف n:) وطلبٌ بهاتف — محجوب.
      final noPhoneRow =
          [triRow(id: 'a1', name: 'محمد أحمد', patientId: 'n:محمد احمد')];
      expect(
        lastTriAnalysisDate(noPhoneRow,
            patientId: 'p:0922:محمد احمد',
            patientName: 'محمد أحمد',
            clinic: 'الصفوة',
            normalize: arNorm),
        today,
      );
      // والعكس: صف بهاتف وطلبٌ بلا هاتف — محجوب.
      final phoneRow =
          [triRow(id: 'a1', name: 'محمد أحمد', patientId: 'p:0911:محمد احمد')];
      expect(
        lastTriAnalysisDate(phoneRow,
            patientName: 'محمد أحمد', clinic: 'الصفوة', normalize: arNorm),
        today,
      );
    });

    test('تطابق المعرّفين = نفس المريض مهما كان (لا استثناء)', () {
      final rows =
          [triRow(id: 'a1', name: 'قديم', patientId: 'p:0911:قديم')];
      expect(
        lastTriAnalysisDate(rows,
            patientId: 'p:0911:قديم',
            patientName: 'اسم جديد',
            clinic: 'الصفوة',
            normalize: arNorm),
        today,
      );
    });
  });

  group('م153/ج — الكاتبان بنطاق العيادة', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('m153_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    JMap config() => {
          'centerName': 'مركز الاختبار',
          'doctorPct': 50,
          'clinics': ['الصفوة', 'كاريزما'],
          'services': ['حشو'],
          'payments': ['كاش', 'تحويل'],
          kTriAnalysesCfgKey: {
            'enabled': true,
            'price': 50,
            'repeatMonths': 6,
          },
        };

    ProviderContainer container() => ProviderContainer(overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
        ]);

    int analCount(ProviderContainer c) => c
        .read(reposProvider)
        .records
        .getAll()
        .where((r) => jsTruthy(r['isAnalysis']))
        .length;

    test('saveNewRecord: نفس الاسم بعيادتين — تحليلٌ في كلٍّ منهما يمرّ، '
        'والتكرار بنفس العيادة يُصَدّ', () {
      final c = container();
      addTearDown(c.dispose);
      final repos = c.read(reposProvider);
      void visit(String clinic, {AnalysisInput? anal}) => saveNewRecord(
            repos,
            config(),
            SaveRecordInput(
              name: 'محمد أحمد',
              date: today,
              amount: 200,
              clinic: clinic,
              service: 'حشو',
              payment: 'كاش',
              analysis: anal,
            ),
          );
      final anal = AnalysisInput(
          name: kTriAnalysesName, price: 50, payment: 'كاش');
      visit('الصفوة', anal: anal);
      expect(analCount(c), 1);
      visit('كاريزما', anal: anal); // عيادة أخرى — حرّ.
      expect(analCount(c), 2, reason: 'كل عيادة مستقلة بقاعدتها');
      visit('الصفوة', anal: anal); // تكرار بنفس العيادة — يُصَدّ.
      expect(analCount(c), 2);
      visit('كاريزما', anal: anal); // تكرار بالثانية — يُصَدّ.
      expect(analCount(c), 2);
    });

    test('addAnalysisToVisit: عيادة أخرى تمرّ ونفسها تُصَدّ', () {
      final c = container();
      addTearDown(c.dispose);
      final repos = c.read(reposProvider);
      String visit(String clinic) => saveNewRecord(
            repos,
            config(),
            SaveRecordInput(
              name: 'محمد أحمد',
              date: today,
              amount: 200,
              clinic: clinic,
              service: 'حشو',
              payment: 'كاش',
            ),
          ).entryId;
      final e1 = visit('الصفوة');
      final e2 = visit('كاريزما');
      bool add(String of, String clinic) => addAnalysisToVisit(repos,
          analysisOf: of,
          patientName: 'محمد أحمد',
          clinic: clinic,
          date: today,
          cfg: config(),
          payment: 'كاش');
      expect(add(e1, 'الصفوة'), isTrue);
      expect(add(e2, 'كاريزما'), isTrue, reason: 'عيادة أخرى مستقلة');
      expect(add(e1, 'الصفوة'), isFalse, reason: 'تكرار بنفس العيادة');
      expect(analCount(c), 2);
    });
  });
}
