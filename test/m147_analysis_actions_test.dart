/// م147 — اختبارات إجراءات التحاليل على زيارةٍ قائمة + تشخيص حقل الملاحظات.
///
/// (أ) addAnalysisToVisit يكتب صفَّ isAnalysis معزولاً مربوطاً بزيارةٍ قائمة
///     بسعر الإعدادات وطريقةٍ مختارة — ويحترم الحارس (ميزة معطّلة/سعر ≤ 0).
/// (ب) تشخيص «المعلومات المختصرة»: notes المحفوظة على صف الزيارة تُقرأ
///     عبر getAll (نفس مصدر عمود الجدول) — إثباتٌ أن مسار البيانات سليم.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/core/utils/js_compat.dart'
    show getCurrentDate, jsTruthy;
import 'package:dental_clinic_flutter/features/records/record_saver.dart';
import 'package:dental_clinic_flutter/features/settings/analyses3.dart'
    show kTriAnalysesCfgKey, kTriAnalysesName;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'staff_test_session.dart' show staffAdminSession;

typedef JMap = Map<String, Object?>;

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('m147_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  JMap config({bool analysesOn = true, num analysesPrice = 50}) => {
        'centerName': 'مركز الاختبار',
        'doctorPct': 50,
        'clinics': ['الصفوة'],
        'services': ['حشو'],
        'payments': ['كاش', 'تحويل'],
        if (analysesOn)
          kTriAnalysesCfgKey: {'enabled': true, 'price': analysesPrice},
      };

  ProviderContainer container() => ProviderContainer(
        overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
        ],
      );

  String today() => getCurrentDate();

  String seedVisit(ProviderContainer c, {String notes = ''}) {
    final repos = c.read(reposProvider);
    final res = saveNewRecord(
      repos,
      config(),
      SaveRecordInput(
        name: 'أحمد',
        date: today(),
        amount: 200,
        clinic: 'الصفوة',
        service: 'حشو',
        payment: 'كاش',
        notes: notes,
      ),
    );
    return res.entryId;
  }

  group('addAnalysisToVisit — إضافة تحليل لزيارة قائمة', () {
    test('يكتب صفاً معزولاً مربوطاً بالزيارة بسعر الإعدادات', () {
      final c = container();
      addTearDown(c.dispose);
      final entryId = seedVisit(c);
      final repos = c.read(reposProvider);
      final ok = addAnalysisToVisit(
        repos,
        analysisOf: entryId,
        patientName: 'أحمد',
        clinic: 'الصفوة',
        date: today(),
        cfg: config(analysesPrice: 50),
        payment: 'تحويل',
      );
      expect(ok, isTrue);
      final anal = repos.records
          .getAll()
          .where((r) => jsTruthy(r['isAnalysis']))
          .toList();
      expect(anal.length, 1);
      expect(anal.first['analysisOf'], entryId);
      expect(anal.first['analysisName'], kTriAnalysesName);
      expect(anal.first['amount'], 50);
      expect(anal.first['payment'], 'تحويل');
      // حرّاس العزل صفر — لا يسلكه أي مسار دين/تركيبة/دفعة.
      expect(anal.first['isDebt'], 0);
      expect(anal.first['isPros'], 0);
      expect(anal.first['isDebtPayment'], 0);
    });

    test('يرفض حين الميزة معطّلة أو السعر ≤ 0 (لا صف شبح)', () {
      final c = container();
      addTearDown(c.dispose);
      final entryId = seedVisit(c);
      final repos = c.read(reposProvider);
      expect(
        addAnalysisToVisit(repos,
            analysisOf: entryId,
            patientName: 'أحمد',
            clinic: 'الصفوة',
            date: today(),
            cfg: config(analysesOn: false),
            payment: 'كاش'),
        isFalse,
      );
      expect(
        addAnalysisToVisit(repos,
            analysisOf: entryId,
            patientName: 'أحمد',
            clinic: 'الصفوة',
            date: today(),
            cfg: config(analysesPrice: 0),
            payment: 'كاش'),
        isFalse,
      );
      expect(
        repos.records.getAll().where((r) => jsTruthy(r['isAnalysis'])).length,
        0,
      );
    });

    test('طريقة غير كاش/تحويل تُطبَّع إلى كاش', () {
      final c = container();
      addTearDown(c.dispose);
      final entryId = seedVisit(c);
      final repos = c.read(reposProvider);
      addAnalysisToVisit(repos,
          analysisOf: entryId,
          patientName: 'أحمد',
          clinic: 'الصفوة',
          date: today(),
          cfg: config(),
          payment: 'شيء غريب');
      final anal =
          repos.records.getAll().firstWhere((r) => jsTruthy(r['isAnalysis']));
      expect(anal['payment'], 'كاش');
    });
  });

  group('تشخيص المعلومات المختصرة — notes تُقرأ عبر getAll', () {
    test('ملاحظة محفوظة على الزيارة تظهر في getAll بمفتاح r:id', () {
      final c = container();
      addTearDown(c.dispose);
      final entryId = seedVisit(c, notes: 'مريض حساس للبنسلين');
      final repos = c.read(reposProvider);
      // نفس منطق بناء خريطة عمود «معلومات مختصرة» في جدول الكمبيوتر.
      final notesMap = <String, String>{};
      for (final r in repos.records.getAll()) {
        final n = '${r['notes'] ?? ''}'.trim();
        if (n.isNotEmpty && n != 'null') notesMap['r:${r['id']}'] = n;
      }
      expect(notesMap['r:$entryId'], 'مريض حساس للبنسلين');
    });
  });
}
