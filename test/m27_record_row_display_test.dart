/// اختبارات م27 — عرض صف السجل (توأم RecordRow.vue) وقاعدة إخفاء أصل
/// الدين وترقيم الدفعات وصيغة التاريخ:
///   • displayService: الدفعة تأخذ اسم خدمة دينها وتُنظَّف البادئات.
///   • شارة نوع الدفعة: سداد كلي/دفعة جزئية.
///   • installmentLabel: «دفعة N» عبر المصدر الموحّد.
///   • التاريخ: YYYY-MM-DD ← DD/MM/YYYY.
///   • قائمة الزيارات تُخفي أصل الدين (isDebt) فلا تظهر قيمته الكاملة.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/core/utils/js_compat.dart';
import 'package:dental_clinic_flutter/features/patients/record_row_logic.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('م27 — دوال عرض الصف النقية', () {
    test('displayService: الدفعة تأخذ خدمة دينها', () {
      final e = {
        'isDebtPayment': true,
        'debtId': 'd1',
        'service': 'دفعة دين — حشو عصب',
      };
      final debt = {'id': 'd1', 'service': 'حشو عصب'};
      expect(recordDisplayService(e, payDebt: debt, isPros: false),
          'حشو عصب');
    });

    test('displayService: تنظيف البادئات واللواحق', () {
      expect(
          recordDisplayService({'service': 'دفعة تركيبات — تاج'},
              isPros: false),
          'تاج');
      expect(
          recordDisplayService({'service': 'حشو (دفعة أولى)'},
              isPros: false),
          'حشو');
    });

    test('displayService: الفارغ ← تركيبات/زيارة', () {
      expect(recordDisplayService({'service': ''}, isPros: true),
          'تركيبات');
      expect(recordDisplayService({'service': ''}, isPros: false),
          'زيارة');
    });

    test('شارة نوع الدفعة: سداد كلي/دفعة جزئية', () {
      expect(payTypeBadge('full'), 'سداد كلي');
      expect(payTypeBadge('partial'), 'دفعة جزئية');
      expect(payTypeBadge(null), 'دفعة جزئية');
    });

    test('صيغة التاريخ DD/MM/YYYY', () {
      expect(fmtDisplayDate('2026-07-15'), '15/07/2026');
      expect(fmtDisplayDate(''), '');
    });

    test('installmentLabel: فارغ لغير الدفعات', () {
      expect(installmentLabelFor({'service': 'حشو'}, null, const []), '');
    });

    test('installmentLabel: «دفعة N» بترتيب كرونولوجي ثابت', () {
      final debt = {
        'id': 'd1',
        'installments': [
          {'id': 'i1', 'recordId': 'r1', 'amount': 100,
            'createdAt': 1000},
          {'id': 'i2', 'recordId': 'r2', 'amount': 100,
            'createdAt': 2000},
        ],
      };
      final rec2 = {'id': 'r2', 'isDebtPayment': true, 'debtId': 'd1'};
      expect(installmentLabelFor(rec2, debt, const []), 'دفعة 2');
    });
  });

  group('م27 — قائمة الزيارات تُخفي أصل الدين', () {
    late Directory tmp;
    late ProviderContainer c;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('m27_');
      c = ProviderContainer(
          overrides: [dbDirProvider.overrideWithValue(tmp.path)]);
    });
    tearDown(() {
      c.dispose();
      tmp.deleteSync(recursive: true);
    });

    test('أصل الدين (isDebt) لا يظهر ضمن الزيارات؛ الدفعات تظهر بمبالغها',
        () {
      final repos = c.read(reposProvider);
      // أصل دين 5000 (isDebt) + دفعتان.
      repos.records.upsertLocal({
        'id': 'orig', 'name': 'محمد', 'patient_name': 'محمد',
        'clinic': 'ع1', 'date': '2026-07-15', 'service': 'حشو عصب',
        'amount': 5000, 'payment': 'دين', 'isDebt': true,
      });
      repos.records.upsertLocal({
        'id': 'pay1', 'name': 'محمد', 'patient_name': 'محمد',
        'clinic': 'ع1', 'date': '2026-07-15', 'service': 'دفعة دين',
        'amount': 1500, 'payment': 'تحويل', 'isDebtPayment': true,
        'debtId': 'dd1', 'debtPaymentType': 'partial',
      });

      // نموذج بناء قائمة الزيارات في الشاشة: استبعاد أصل الدين
      // (jsTruthy يطابق تخزين 1/true/'1' — كما في الشاشة حرفياً).
      final all = repos.records.getAll();
      final visits =
          all.where((r) => !jsTruthy(r['isDebt'])).toList();
      final origInVisits = visits.where((r) => r['id'] == 'orig');
      final payInVisits = visits.where((r) => r['id'] == 'pay1');
      expect(origInVisits, isEmpty,
          reason: 'قيمة الدين الكاملة 5000 يجب ألا تظهر في السجلات');
      expect(payInVisits, hasLength(1),
          reason: 'الدفعة تظهر بمبلغها المدفوع');
      expect(payInVisits.single['amount'], 1500);
    });
  });
}
