/// اختبارات م29 — فرز الزيارات byNewestFirst وإعادة ترقيم الدفعات عند الحذف:
///   • الأخيرة (activityAt أحدث) دائماً بالأعلى حتى ضمن اليوم نفسه.
///   • حذف «دفعة 2» ⇒ الثالثة تصير «دفعة 2» (الترقيم على الأقساط النشطة).
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/features/archive/month_stats.dart'
    show byNewestFirst;
import 'package:dental_clinic_flutter/features/finance/debt_actions.dart';
import 'package:dental_clinic_flutter/features/finance/treasury_logic.dart'
    show installmentSeqForRecord;
import 'package:dental_clinic_flutter/features/patients/profile_actions.dart'
    show deleteEntryCascade;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('م29/1 — الفرز byNewestFirst', () {
    test('نفس اليوم: الأحدث نشاطاً أولاً ثم كسر التعادل بالمعرّف', () {
      final rows = [
        {'id': 'a', 'date': '2026-07-27', '_activityAt': 1000},
        {'id': 'b', 'date': '2026-07-27', '_activityAt': 3000},
        {'id': 'c', 'date': '2026-07-27', '_activityAt': 2000},
      ]..sort(byNewestFirst);
      expect(rows.map((r) => r['id']).toList(), ['b', 'c', 'a'],
          reason: 'الأحدث activityAt بالأعلى');
    });
  });

  group('م29/2 — إعادة الترقيم عند حذف دفعة', () {
    late Directory tmp;
    late ProviderContainer c;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('m29_');
      c = ProviderContainer(
          overrides: [dbDirProvider.overrideWithValue(tmp.path)]);
    });
    tearDown(() {
      c.dispose();
      tmp.deleteSync(recursive: true);
    });

    test('حذف دفعة 2 يجعل الثالثة دفعة 2', () {
      final repos = c.read(reposProvider);
      final cfg = {'doctorPct': 50, 'clinics': ['ع1']};
      // دين بثلاث دفعات متتابعة.
      repos.debts.upsertLocal({
        'id': 'd1', 'name': 'سالم', 'patient_name': 'سالم',
        'clinic': 'ع1', 'service': 'حشو', 'date': '2026-07-27',
        'totalAmount': 3000, 'paidAmount': 0, 'remaining': 3000,
        'status': 'partial', 'installments': const [],
      });
      for (var i = 0; i < 3; i++) {
        payDebtInstallment(repos, cfg, repos.debts.getById('d1')!,
            amount: 500, date: '2026-07-27', payment: 'كاش');
      }
      var debt = repos.debts.getById('d1')!;
      final insts = [...?(debt['installments'] as List?)];
      expect(insts, hasLength(3));
      // السجل المرتبط بالقسط الثاني.
      final rec2Id = '${insts[1]['recordId']}';
      final rec2 = repos.records.getById(rec2Id)!;
      expect(installmentSeqForRecord(debt, repos.records.getAll(), rec2),
          2);
      final rec3Id = '${insts[2]['recordId']}';

      // احذف دفعة 2 (سجلها) — الاكتساح يزيل قسطه ويعيد الاشتقاق.
      deleteEntryCascade(repos, cfg, id: rec2Id, source: 'r');
      debt = repos.debts.getById('d1')!;
      final rec3 = repos.records.getById(rec3Id)!;
      expect(
          installmentSeqForRecord(debt, repos.records.getAll(), rec3), 2,
          reason: 'بعد حذف الثانية تصبح الثالثة دفعة 2');
      expect([...?(debt['installments'] as List?)], hasLength(2));
    });
  });
}
