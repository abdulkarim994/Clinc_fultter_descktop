/// اختبارات م66/دفعة صفر-ج — ذرّية مسارات المال متعددة الكتابات.
///
/// العيب الأصلي (DATA-3): حفظ الزيارة والدفع والحذف كانت سلاسل upsert بلا
/// معاملة. انهيار في المنتصف يترك حالة نصفية (دين بلا سجل دفعته، دخل مختل)
/// بلا مسار إصلاح. الإصلاح: LocalDb.transaction بـ SAVEPOINT متداخلة، وركلة
/// مزامنة واحدة بعد الالتزام.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/core/utils/js_compat.dart';
import 'package:dental_clinic_flutter/features/records/record_saver.dart'
    hide JMap;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('m66t_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Map<String, Object?> config() => {
        'centerName': 'مركز', 'doctorPct': 50,
        'clinics': ['الصفوة'], 'services': ['حشو'], 'payments': ['كاش'],
      };

  ({ProviderContainer c, dynamic repos, dynamic db}) boot() {
    final c = ProviderContainer(
        overrides: [dbDirProvider.overrideWithValue(tmp.path)]);
    return (c: c, repos: c.read(reposProvider), db: c.read(localDbProvider));
  }

  group('م66 — LocalDb.transaction', () {
    test('الفشل داخل المعاملة يُرجع كل الكتابات (لا حالة نصفية)', () {
      final b = boot();
      addTearDown(b.c.dispose);
      try {
        b.db.transaction(() {
          b.repos.patients.upsert({'id': 'ن1', 'name': 'ن1', 'patient_name': 'ن1'});
          b.repos.debts.upsert({'id': 'د1', 'patient_name': 'ن1', 'total_amount': 100});
          throw StateError('انهيار محاكى في منتصف العملية');
        });
        fail('كان يجب أن يُعاد رمي الاستثناء');
      } catch (_) {/* متوقَّع */}

      expect(b.repos.patients.getById('ن1'), isNull,
          reason: 'كتابة المريض تراجعت');
      expect(b.repos.debts.getById('د1'), isNull,
          reason: 'كتابة الدين تراجعت');
    });

    test('النجاح يثبّت كل الكتابات', () {
      final b = boot();
      addTearDown(b.c.dispose);
      b.db.transaction(() {
        b.repos.patients.upsert({'id': 'ن2', 'name': 'ن2', 'patient_name': 'ن2'});
        b.repos.debts.upsert({'id': 'د2', 'patient_name': 'ن2', 'total_amount': 100});
      });
      expect(b.repos.patients.getById('ن2'), isNotNull);
      expect(b.repos.debts.getById('د2'), isNotNull);
    });

    test('التداخل: فشل داخلي يُرجع الداخل ويُبقي الخارج (SAVEPOINT)', () {
      final b = boot();
      addTearDown(b.c.dispose);
      b.db.transaction(() {
        b.repos.patients.upsert({'id': 'خارج', 'name': 'خارج', 'patient_name': 'خارج'});
        try {
          b.db.transaction(() {
            b.repos.patients.upsert({'id': 'داخل', 'name': 'داخل', 'patient_name': 'داخل'});
            throw StateError('فشل داخلي');
          });
        } catch (_) {/* يُبتلع — الخارج يكمل */}
      });
      expect(b.repos.patients.getById('خارج'), isNotNull,
          reason: 'الخارج التزم');
      expect(b.repos.patients.getById('داخل'), isNull,
          reason: 'الداخل تراجع إلى نقطة الحفظ');
    });

    test('الركلة مؤجَّلة: مرة واحدة بعد الالتزام لا لكل صف', () {
      final b = boot();
      addTearDown(b.c.dispose);
      var kicks = 0;
      b.db.setSyncKicker(() => kicks++);
      b.db.transaction(() {
        b.repos.patients.upsertLocal({'id': 'ك1', 'name': 'ك1'});
        b.repos.patients.upsertLocal({'id': 'ك2', 'name': 'ك2'});
        b.repos.patients.upsertLocal({'id': 'ك3', 'name': 'ك3'});
        expect(kicks, 0, reason: 'لا ركلة أثناء المعاملة');
      });
      expect(kicks, 1, reason: 'ركلة واحدة بعد الالتزام');
    });

    test('حفظ زيارة بدين: العملية كلها موجودة بعد النجاح', () {
      final b = boot();
      addTearDown(b.c.dispose);
      saveNewRecord(
          b.repos, config(),
          SaveRecordInput(
            name: 'سعاد', date: getCurrentDate(), amount: 1000,
            clinic: 'الصفوة', service: 'حشو', payment: 'كاش',
            isDebt: true, firstPay: 200,
          ));
      expect(b.repos.debts.getAll().length, 1);
      expect(b.repos.patients.getById('سعاد'), isNotNull);
      // سجل الدفعة الأولى موجود
      expect(b.repos.records.getAll().where((r) => jsTruthy(r['isDebtPayment'])).length, 1);
    });
  });
}
