/// اختبارات م189 — بلاغات المالك الثلاثة، وجذرُها الأول مُثبَتٌ بالبيانات.
///
/// **(أ) الملف الفارغ:** «عم اختار متابعة على مسؤوليتي مع أن المريض له رقم
/// هاتف… رغم هذا ينشأ ملف فارغ بسجلات المريض». لقطتُه أظهرت الدليل الحاسم:
/// الملف الشبح يحمل الرقم **بلا صفر البدء** (`919292281`) والحقيقيُّ بصفره
/// (`0919292281`) — فشكلان لرقمٍ واحد في فضاء هويةٍ واحد:
///   • هاتف الصفّ كان يُقرأ بأرقامه الخام (بصفر البدء).
///   • والهاتف المسكوك في `patient_id` يمرّ على التطبيع القانوني
///     (`patientKeyFor` ⇒ `normPhone`) فيسقط صفر البدء.
/// فأيُّ صفٍّ يرث هويته من المعرّف (صفّ التحليل) يصير **هويةً أخرى** لنفس
/// الشخص ⇒ ملفٌ ثالث بصفر زيارات. العلاج: التطبيع في كلا المصدرين ⇒ الملف
/// الشبح **يذوب قراءةً** بلا أي هجرة بيانات (قرار المالك).
///
/// **(ب) عمود الهاتف** في سجل التحاليل: صفوف ما قبل م189 كُتبت بلا هاتف،
/// فيورَّث من زيارتها الأصل عبر `analysisOf`.
///
/// **(ج) الأرشفة:** «الضغط على اسم واحد يحدد الكل، والإلغاء يلغي الكل —
/// نظام الأرشفة يعتبرهم شخصاً واحداً»: المفتاح كان «اسم|عيادة» بلا هاتف.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/data/db/local_db.dart';
import 'package:dental_clinic_flutter/data/repositories/repositories.dart';
import 'package:dental_clinic_flutter/features/patients/archive_store.dart';
import 'package:dental_clinic_flutter/features/patients/clinic_scope.dart'
    as scope show clinicScopedKey, medicalScopedKey;
import 'package:dental_clinic_flutter/features/patients/patients_logic.dart';
import 'package:dental_clinic_flutter/core/utils/ar_normalize.dart'
    show arNorm, normPhone;
import 'package:dental_clinic_flutter/features/records/record_saver.dart'
    show SaveRecordInput, addAnalysisToVisit, saveNewRecord;
import 'package:dental_clinic_flutter/features/settings/analyses3.dart'
    show kTriAnalysesCfgKey, lastTriAnalysisHit;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

typedef JMap = Map<String, Object?>;

const _name = 'محمد حسين';
const _clinic = 'الحياة';

/// زيارةٌ عادية بهاتفها الخام كما يكتبه المستخدم (بصفر البدء).
JMap visit({
  required String id,
  required String phone,
  required num amount,
  String date = '2026-08-19',
}) => {
      'id': id,
      'name': _name,
      'patient_name': _name,
      'clinic': _clinic,
      'clinic_id': _clinic,
      'phone': phone,
      'patient_id': 'p:${phone.replaceFirst(RegExp('^0+'), '')}:$_name',
      'service': 'حشو',
      'date': date,
      'amount': amount,
      'payment': 'كاش',
      'isDebt': 0,
      'isPros': 0,
      'isDebtPayment': 0,
      '_t': 'r',
    };

/// صفّ تحليلٍ **كما كان يُكتب قبل م189**: بلا عمود هاتف، ومعرّفه المسكوك
/// مطبَّع (بلا صفر البدء) — وهو منشأ الملف الشبح.
JMap oldAnalysis({
  required String id,
  required String analysisOf,
  String? mintedPid,
  String date = '2026-08-19',
}) => {
      'id': id,
      'name': _name,
      'patient_name': _name,
      'clinic': _clinic,
      'clinic_id': _clinic,
      'patient_id': ?mintedPid,
      'service': 'تحاليل',
      'date': date,
      'amount': 25,
      'payment': 'كاش',
      'isAnalysis': 1,
      'isDebt': 0,
      'isPros': 0,
      'isDebtPayment': 0,
      'analysisName': 'التحاليل الثلاثية',
      'analysisOf': analysisOf,
      '_t': 'r',
    };

void main() {
  group('م189/أ — شكلٌ واحدٌ للهاتف في فضاء الهوية', () {
    test('هاتف العمود وهاتف المعرّف المسكوك يتّحدان قانونياً', () {
      final col = <String, Object?>{'phone': '0919292281'};
      final pid = <String, Object?>{'patient_id': 'p:919292281:$_name'};
      final idx = IdentityIndex(const [], const [], const []);
      expect(idx.phoneOf(col), idx.phoneOf(pid),
          reason: 'م189: شكلان لرقمٍ واحد كانا هويتين');
      expect(idx.phoneOf(col), '919292281');
      // ويستوي معهما الشكل الدولي (نفس تطبيع الخلفية).
      expect(idx.phoneOf(<String, Object?>{'phone': '+218 91 929 2281'}),
          '919292281');
    });

    test('الملف الشبح يذوب: ملفان لا ثلاثة — والقيم لا تختلط', () {
      // سيناريو اللقطة: سميّان بهاتفين، وتحليلٌ قديم بلا هاتف لأحدهما.
      final recs = <JMap>[
        visit(id: 'v1', phone: '0919292288', amount: 1500),
        visit(id: 'v2', phone: '0919292281', amount: 250),
        oldAnalysis(
            id: 'a1', analysisOf: 'v2', mintedPid: 'p:919292281:$_name'),
      ];
      final map = buildPatientMap(recs, const [], const []);
      expect(map.length, 2, reason: 'كان ثلاثة: الثالث شبحٌ بصفر زيارات');
      final aggs = map.values.toList()
        ..sort((a, b) => a.total.compareTo(b.total));
      expect(aggs[0].total, 250);
      expect(aggs[0].visitCount, 1);
      expect(aggs[1].total, 1500);
      // وصفّ التحليل التحق بصاحبه (لا يزيد زيارةً ولا مالاً — عزلٌ مالي).
      expect(aggs[0].entries.length, 2);
    });

    test('العرض بالرقم كما كُتب (بصفر البدء) لا بالقانوني', () {
      final recs = <JMap>[
        visit(id: 'v1', phone: '0919292288', amount: 1500),
        visit(id: 'v2', phone: '0919292281', amount: 250),
      ];
      final phones = {
        for (final p in buildPatientMap(recs, const [], const []).values)
          p.phone,
      };
      expect(phones, {'0919292288', '0919292281'},
          reason: 'م189: الهوية قانونية والعرض خام — كلٌّ في بابه');
    });

    test('صفٌّ بلا هاتفٍ ولا معرّف يرث هوية زيارته (م181 مصونة)', () {
      final recs = <JMap>[
        visit(id: 'v1', phone: '0919292281', amount: 250),
        oldAnalysis(id: 'a1', analysisOf: 'v1'), // بلا هاتف ولا معرّف
      ];
      final map = buildPatientMap(recs, const [], const []);
      expect(map.length, 1);
      final idx = IdentityIndex(recs, const [], const []);
      expect(idx.phoneOf(recs[1]), '919292281');
    });
  });

  group('م189/ج — الأرشفة تعزل السميَّين', () {
    test('مفتاح الهوية يفرّق بينهما ومفتاح الاسم يوحّدهما', () {
      final a = scope.medicalScopedKey(_name, _clinic, '0919292288');
      final b = scope.medicalScopedKey(_name, _clinic, '0919292281');
      expect(a, isNot(b));
      expect(scope.clinicScopedKey(_name, _clinic),
          isNot(a), reason: 'المفتاح القديم لا يميّز — وهو أصل البلاغ');
    });

    test('حالة الأرشفة: مؤرشفٌ هو وحده — وسميُّه نشط', () {
      final keys = <String>{scope.medicalScopedKey(_name, _clinic, '0919292288')};
      final one = PatientAgg(_name, _clinic, 'p:919292288');
      one.noteRawPhone('0919292288');
      final two = PatientAgg(_name, _clinic, 'p:919292281');
      two.noteRawPhone('0919292281');
      expect(aggArchived(keys, one), isTrue);
      expect(aggArchived(keys, two), isFalse,
          reason: 'م189: أرشفةُ سميٍّ لا تُخفي سميَّه');
    });

    test('توافقٌ خلفي: أرشفةٌ قديمة بمفتاح الاسم تبقى سارية لغير المتشابه',
        () {
      final keys = <String>{scope.clinicScopedKey(_name, _clinic)};
      final lone = PatientAgg(_name, _clinic); // مجموعةٌ غير منقسمة
      lone.noteRawPhone('0919292281');
      expect(aggArchived(keys, lone), isTrue,
          reason: 'مرضى ما قبل م189 لا تُفقد أرشفتهم');
      // أما المتشابهون فلا يجمعهم المفتاح القديم في مصيرٍ واحد.
      final twin = PatientAgg(_name, _clinic, 'p:919292281');
      twin.noteRawPhone('0919292281');
      expect(aggArchived(keys, twin), isFalse);
    });

    test('الدفعة تؤرشف كل هويةٍ بمفتاحها (لا مفتاحاً واحداً للجميع)', () {
      final tmp = Directory.systemTemp.createTempSync('m189_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final db = LocalDb.open(p.join(tmp.path, 'dental_clinic_offline.db'));
      addTearDown(db.close);
      final store = PatientArchiveStore(Repositories(db).settings);
      store.archiveAll([
        (name: _name, clinic: _clinic, phone: '0919292288'),
      ]);
      expect(store.isArchived(_name, _clinic, '0919292288'), isTrue);
      expect(store.isArchived(_name, _clinic, '0919292281'), isFalse,
          reason: 'م189: الدفعة تعزل — كانت تؤرشف الاسم كله');
      store.unarchiveAll([
        (name: _name, clinic: _clinic, phone: '0919292288'),
      ]);
      expect(store.isArchived(_name, _clinic, '0919292288'), isFalse);
    });
  });

  group('م189/أ — الكاتب والبوابة: هويةٌ كاملة على صفّ التحليل', () {
    test('الصفّ الجديد يحمل الهاتف والمعرّف — فلا ملفَ فارغاً', () {
      final tmp = Directory.systemTemp.createTempSync('m189w_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final db = LocalDb.open(p.join(tmp.path, 'dental_clinic_offline.db'));
      addTearDown(db.close);
      final repos = Repositories(db);
      final cfg = <String, Object?>{
        'clinics': [_clinic],
        'services': ['حشو'],
        'payments': ['كاش', 'تحويل'],
        kTriAnalysesCfgKey: {
          'enabled': true,
          'price': 25,
          'repeatMonths': 6,
        },
      };
      final vid = saveNewRecord(
        repos,
        cfg,
        SaveRecordInput(
          name: _name,
          date: '2026-08-19',
          amount: 250,
          clinic: _clinic,
          service: 'حشو',
          payment: 'كاش',
          phone: '0919292281',
        ),
      ).entryId;
      expect(
          addAnalysisToVisit(repos,
              analysisOf: vid,
              patientName: _name,
              clinic: _clinic,
              date: '2026-08-19',
              cfg: cfg,
              payment: 'كاش',
              phone: '0919292281'),
          isTrue);
      final row = repos.records
          .getAll()
          .cast<JMap>()
          .firstWhere((r) => r['isAnalysis'] == 1);
      expect('${row['phone']}', '0919292281',
          reason: 'م189: كان يُكتب بلا هاتف إطلاقاً');
      expect('${row['patient_id']}', startsWith('p:919292281:'),
          reason: 'ويُسكّ معرّفه فتُعرف هويته حتماً');
      // والأهم: ملفٌ واحد لا اثنان (زيارةٌ واحدة — التحليل لا يزيدها).
      final map = buildPatientMap(
          repos.records.getAll().cast<JMap>(), const [], const []);
      expect(map.length, 1);
      expect(map.values.first.visitCount, 1);
      expect(map.values.first.total, 250);
    });

    test('الحلّال الموروث يجعل الهوية مؤكَّدة ⇒ حجبٌ لا تحذير', () {
      // صفُّ تحليلٍ قديم بلا هاتف، وزيارتُه تحمل الرقم.
      final rows = <JMap>[
        visit(id: 'v1', phone: '0919292281', amount: 250),
        oldAnalysis(id: 'a1', analysisOf: 'v1'),
      ];
      final idx = IdentityIndex(rows, const [], const []);
      String norm(String s) => normPhone(s);
      final blind = lastTriAnalysisHit(rows,
          patientName: _name,
          phone: '0919292281',
          normalize: arNorm,
          normPhone: norm);
      expect(blind?.certain, isFalse,
          reason: 'بلا حلّال: الصفّ يبدو بلا هاتف ⇒ تحذيرٌ أعمى (البلاغ)');
      final seeing = lastTriAnalysisHit(rows,
          patientName: _name,
          phone: '0919292281',
          normalize: arNorm,
          normPhone: norm,
          phoneOfRow: idx.phoneOf);
      expect(seeing?.certain, isTrue,
          reason: 'م189: يرث هاتف زيارته ⇒ هويةٌ مؤكَّدة');
      // وسميُّه بهاتفٍ آخر لا يُحجب ولا يُحذَّر أصلاً.
      expect(
          lastTriAnalysisHit(rows,
              patientName: _name,
              phone: '0919292288',
              normalize: arNorm,
              normPhone: norm,
              phoneOfRow: idx.phoneOf),
          isNull);
    });
  });
}
