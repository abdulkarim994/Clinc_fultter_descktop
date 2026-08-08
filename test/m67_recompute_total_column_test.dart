/// اختبارات م67/دفعة أول-ب — إعادة حساب الدين تقرأ العمود total_amount.
///
/// العيب الأصلي (H5): recomputeDebts كانت تقرأ الإجمالي من total أو
/// totalAmount فقط. دينٌ كتبه تطبيق Vue القديم بالإجمالي في العمود
/// snake_case `total_amount` وحده يُعاد حسابه إلى إجمالي صفر ⇒ متبقٍ صفر ⇒
/// حالة «مسدَّد» — دين يُشطب بصمت من قوائم الديون ومن المجاميع.
library;

import 'package:dental_clinic_flutter/data/sync/merge/recompute.dart';
import 'package:dental_clinic_flutter/core/utils/js_compat.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('م67 — recomputeDebts والعمود total_amount', () {
    test('REPRO: الإجمالي في total_amount وحده لا يُشطب الدين', () {
      // شكل صف Vue قديم: الإجمالي في العمود snake_case فقط، بلا total/totalAmount.
      final row = <String, Object?>{
        'id': 'd-vue', 'type': 'regular', 'total_amount': 1000,
        'installments': [
          {'id': 'i1', 'amount': 300},
        ],
      };
      final out = recomputeDebts(row);
      expect(jsNumOr0(out['paidAmount']), 300);
      expect(jsNumOr0(out['remaining']), 700,
          reason: 'م67: 1000 - 300 لا صفر');
      expect(out['status'], 'partial',
          reason: 'م67: ليس «مسدَّد» بالخطأ');
    });

    test('دين بلا دفعات في العمود وحده يبقى غير مسدَّد', () {
      final out = recomputeDebts(<String, Object?>{
        'id': 'd2', 'type': 'regular', 'total_amount': 500,
        'installments': const [],
      });
      expect(jsNumOr0(out['remaining']), 500);
      expect(out['status'], 'unpaid',
          reason: 'العيب كان يجعله «مسدَّد» بإجمالي صفر');
    });

    test('أولوية القراءة: total الطازج يفوز على العمود القديم', () {
      final out = recomputeDebts(<String, Object?>{
        'id': 'd3', 'type': 'regular',
        'total': 2000, 'total_amount': 1000, // الطازج 2000
        'installments': [{'id': 'i', 'amount': 500}],
      });
      expect(jsNumOr0(out['remaining']), 1500, reason: '2000 - 500');
    });

    test('التركيبة: الإجمالي في العمود وحده يحسب الحصص صحيحاً', () {
      final out = recomputeProsthetics(<String, Object?>{
        'id': 'p1', 'total_amount': 1000, 'labValue': 200,
        '_rateSnapshot': {'doctorPct': 40},
      });
      // الربح 800، حصة الطبيب 40% = 320، العيادة 480
      expect(jsNumOr0(out['doctorShare']), 320,
          reason: 'م67: لا يُحسب على إجمالي صفر');
      expect(jsNumOr0(out['clinicShare']), 480);
    });
  });
}
