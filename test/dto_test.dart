/// اختبارات DTO — مطابقة التحويلات الحقلية مع سلوك JS الأصلي حرفياً،
/// بما فيها سقطات `||` المقصودة في الحقول المالية.
library;

import 'package:dental_clinic_flutter/data/dto/dto.dart';
import 'package:dental_clinic_flutter/data/sync/feature_flags.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(syncFlags.resetForTest);

  group('toDebtDto', () {
    test('totalAmount falls back to total; remaining clamps at 0', () {
      final d = toDebtDto({
        'id': 'd1',
        'name': 'أحمد',
        'total': 300, // no totalAmount → fallback
        'paidAmount': 400, // overpaid
      })!;
      expect(d['totalAmount'], 300);
      expect(d['total'], 300);
      expect(d['remaining'], 0); // clamped
      expect(d['status'], 'unpaid');
      expect(d['type'], 'normal');
      expect(toDebtDto(null), isNull);
    });

    test('toDebtDb stamps _mod and defaults', () {
      final db = toDebtDb({'id': 'd1', 'name': 'أ', 'totalAmount': 100});
      expect(db['total'], 100);
      expect(db['paidAmount'], 0);
      expect(db['status'], 'unpaid');
      expect(db['_mod'], isA<int>());
    });
  });

  group('toRecordDto', () {
    test('coerces numbers and booleans like JS', () {
      final r = toRecordDto({
        'id': 'r1',
        'amount': '150.5', // numeric string
        'isDebt': 1, // truthy int
        'isPros': 0, // falsy int
        'doctorShare': null,
      })!;
      expect(r['amount'], 150.5);
      expect(r['isDebt'], isTrue);
      expect(r['isPros'], isFalse);
      expect(r['doctorShare'], 0);
      expect(r['payment'], '');
      expect(r['debtId'], isNull);
    });
  });

  group('toAppointmentDto', () {
    test('name falls back to patient_name; keys derived; existing kept', () {
      final a = toAppointmentDto({
        'id': 'a1',
        'patient_name': ' سالم ',
        'clinic': ' ع1 ',
      })!;
      expect(a['name'], ' سالم ');
      expect(a['status'], 'scheduled');
      expect(a['clinic_id'], 'ع1');
      expect(a['patient_id'], 'سالم'); // legacy TRIM key

      final b = toAppointmentDto({
        'id': 'a2',
        'name': 'خالد',
        'clinic': 'ع1',
        'clinic_id': 'CID-SYNCED',
        'patient_id': 'PID-SYNCED',
      })!;
      expect(b['clinic_id'], 'CID-SYNCED'); // never overwritten
      expect(b['patient_id'], 'PID-SYNCED');
    });

    test('toAppointmentDb derives keys deterministically', () {
      final db = toAppointmentDb({
        'id': 'a1',
        'name': 'سالم',
        'date': '2026-08-01',
        'clinic': 'ع2',
      });
      expect(db['clinic_id'], 'ع2');
      expect(db['patient_id'], 'سالم');
      expect(db['status'], 'scheduled');
    });
  });

  group('toPatientDto', () {
    test('defaults and list guards', () {
      final missingId = toPatientDto({'name': 'أحمد'})!;
      expect(missingId['id'], 'أحمد'); // id falls back to name
      expect(missingId['services'], isEmpty);
      expect(missingId['hasDebt'], isFalse);
      expect(toPatientDtoList('not a list'), isEmpty);
      expect(toPatientDtoList([{'id': 'p', 'name': 'ن'}]).length, 1);
    });
  });
}
