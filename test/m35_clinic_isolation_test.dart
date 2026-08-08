/// اختبارات م35 — العزل الكامل للمريض حسب العيادة (قرار مالك v12):
/// نفس الاسم في عيادتين = مريضان مستقلان — تجميعتان وبطاقتان طبيتان
/// وخطتان علاجيتان، وحذف/إعادة تسمية لا تعبر حدود العيادة.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/features/patients/clinic_scope.dart';
import 'package:dental_clinic_flutter/features/patients/patients_logic.dart';
import 'package:dental_clinic_flutter/features/patients/profile_actions.dart'
    show deletePatientData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('م35/1 — مساعد النطاق (نقي)', () {
    test('قراءة متدرجة: مفتاح العيادة أولاً وإلا الإرث بالاسم', () {
      final map = {'سالم': 'إرث', 'سالم|ع1': 'معزول'};
      expect(clinicScopedRead(map, 'سالم', 'ع1'), 'معزول');
      expect(clinicScopedRead(map, 'سالم', 'ع2'), 'إرث',
          reason: 'لا مدخل للعيادة 2 ⇒ الإرث يظهر (لا فقدان)');
      expect(clinicScopedRead(map, 'غائب', 'ع1'), isNull);
    });

    test('الكتابة لمفتاح العيادة وحده (نسخ-عند-الكتابة)', () {
      final out =
          clinicScopedWrite({'سالم': 'إرث'}, 'سالم', 'ع2', 'جديد');
      expect(out['سالم|ع2'], 'جديد');
      expect(out['سالم'], 'إرث', reason: 'الإرث يبقى للعيادة الأخرى');
    });

    test('إعادة التسمية تهاجر مفتاح العيادة وتحفظ الإرث للغير', () {
      final out = clinicScopedRename(
          {'قديم': 'خطة'}, 'قديم', 'جديد', 'ع1',
          othersStillUseLegacy: true);
      expect(out['جديد|ع1'], 'خطة');
      expect(out['قديم'], 'خطة',
          reason: 'عيادة أخرى ما زالت تستعمل الاسم القديم');
      final out2 = clinicScopedRename(
          {'قديم': 'خطة'}, 'قديم', 'جديد', 'ع1',
          othersStillUseLegacy: false);
      expect(out2.containsKey('قديم'), isFalse);
    });
  });

  group('م35/2 — التجميع والحذف المعزولان', () {
    late Directory tmp;
    late ProviderContainer c;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('m35_');
      c = ProviderContainer(
          overrides: [dbDirProvider.overrideWithValue(tmp.path)]);
    });
    tearDown(() {
      c.dispose();
      tmp.deleteSync(recursive: true);
    });

    void seedTwoClinics(dynamic repos) {
      repos.records.upsertLocal({
        'id': 'r1', 'name': 'سالم', 'patient_name': 'سالم',
        'clinic': 'ع1', 'service': 'حشو', 'date': '2026-07-20',
        'amount': 100, 'payment': 'كاش',
      });
      repos.records.upsertLocal({
        'id': 'r2', 'name': 'سالم', 'patient_name': 'سالم',
        'clinic': 'ع2', 'service': 'تنظيف', 'date': '2026-07-21',
        'amount': 300, 'payment': 'كاش',
      });
      repos.debts.upsertLocal({
        'id': 'd1', 'name': 'سالم', 'patient_name': 'سالم',
        'clinic': 'ع2', 'service': 'تقويم', 'date': '2026-07-22',
        'totalAmount': 900, 'paidAmount': 0, 'remaining': 900,
        'status': 'partial', 'installments': const [],
      });
    }

    test('تجميعتان مستقلتان بمفتاح (اسم|عيادة) وإجماليات منفصلة', () {
      final repos = c.read(reposProvider);
      seedTwoClinics(repos);
      final map = buildPatientMap(repos.records.getAll(),
          repos.prosthetics.getAll(), repos.debts.getAll());
      expect(map.containsKey('سالم|ع1'), isTrue);
      expect(map.containsKey('سالم|ع2'), isTrue);
      expect(map.containsKey('سالم'), isFalse);
      expect(map['سالم|ع1']!.total, 100);
      expect(map['سالم|ع1']!.debtRemaining, 0,
          reason: 'دين ع2 لا يتسرب لبطاقة ع1');
      expect(map['سالم|ع2']!.debtRemaining, 900);
      // مرضى كل عيادة: تجميعة عيادتها فقط.
      final rows1 = clinicPatients('ع1',
          patientMap: map,
          records: repos.records.getAll(),
          prosthetics: repos.prosthetics.getAll(),
          debts: repos.debts.getAll());
      expect(rows1, hasLength(1));
      expect(rows1.first.agg.clinic, 'ع1');
      expect(rows1.first.hasDebt, isFalse,
          reason: 'شارة الدين من ديون ع1 وحدها');
    });

    test('حذف مريض عيادة لا يمس نظيره في الأخرى (صفوف وطبية وخطة)', () {
      final repos = c.read(reposProvider);
      seedTwoClinics(repos);
      final cfg = {
        'patientMedical': {
          'سالم': {'conditions': ['ضغط']},        // إرث مشترك
          'سالم|ع1': {'conditions': ['سكري']},    // معزول ع1
        },
        'treatmentPlans': {
          'سالم|ع1': [{'t': 'مرحلة'}],
        },
      };
      // م142 — التوقيع اتّسع ليقبل db + meter (تعطّف R2/الحصة). نمرّر
      // القناتين من الحاوية؛ لا صور أشعة هنا فلا أثر جانبي.
      deletePatientData(
        repos,
        cfg,
        name: 'سالم',
        clinic: 'ع1',
        db: c.read(localDbProvider),
        meter: c.read(storageMeterProvider),
      );
      // صفوف ع1 حُذفت وصفوف ع2 باقية.
      expect(repos.records.getById('r1'), isNull);
      expect(repos.records.getById('r2'), isNotNull);
      expect(repos.debts.getById('d1'), isNotNull);
      // الطبية/الخطة: مدخل ع1 زال، والإرث بقي (ع2 ما زالت موجودة).
      final med =
          c.read(reposProvider).settings.get('app.config') as Map;
      expect((med['patientMedical'] as Map).containsKey('سالم|ع1'),
          isFalse);
      expect((med['patientMedical'] as Map).containsKey('سالم'), isTrue,
          reason: 'الإرث باقٍ لأن سالم ع2 ما زال موجوداً');
      expect((med['treatmentPlans'] as Map).containsKey('سالم|ع1'),
          isFalse);
    });

    test('إعادة تسمية في عيادة لا تمس صفوف الأخرى', () {
      final repos = c.read(reposProvider);
      seedTwoClinics(repos);
      editPatientCascade(repos,
          origName: 'سالم', newName: 'سالم الجديد', clinic: 'ع1');
      expect(repos.records.getById('r1')!['name'], 'سالم الجديد');
      expect(repos.records.getById('r2')!['name'], 'سالم',
          reason: 'مريض ع2 مستقل — لا يُعاد تسميته');
    });
  });
}
