/// اختبارات م108 — دمج الدفعات في جدول معالجتها (خدمة الأساس):
/// بادئات «دفعة دين/تركيبات — X» تُجرَّد، والتسميات المجردة تقرأ
/// خدمة الأساس من لقطة النسب (treatmentId)، والأرقام لا تتغير.
library;

import 'package:dental_clinic_flutter/features/print/treatment_tables.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('م108/أ — baseServiceOf', () {
    test('تجريد البادئات', () {
      expect(baseServiceOf({'service': 'دفعة دين — حشو عصب'}), 'حشو عصب');
      expect(baseServiceOf({'service': 'دفعة تركيبات — زيركون'}), 'زيركون');
    });
    test('التسميات المجردة تقرأ لقطة النسب', () {
      expect(
        baseServiceOf({
          'service': 'دفعة أولى (دين)',
          '_rateSnapshot': {'treatmentId': 'خلع', 'doctorPct': 30},
        }),
        'خلع',
      );
      // لقطة تركيبات (__prosthetics__) لا تصلح اسماً ⇒ تبقى التسمية.
      expect(
        baseServiceOf({
          'service': 'تركيبات (دفعة أولى)',
          '_rateSnapshot': {'treatmentId': '__prosthetics__'},
        }),
        'تركيبات (دفعة أولى)',
      );
      // بلا لقطة ⇒ التسمية كما هي (بيانات قديمة جداً — لا رمي).
      expect(baseServiceOf({'service': 'دفعة أولى (دين)'}),
          'دفعة أولى (دين)');
    });
    test('الخدمات العادية تمر كما هي', () {
      expect(baseServiceOf({'service': 'حشو عصب'}), 'حشو عصب');
      expect(baseServiceOf({}), 'أخرى');
    });
  });

  group('م108/ب — الدمج في buildTreatmentTables', () {
    test('دفعة الدين تهبط صفاً داخل جدول معالجتها والأرقام تتجمع', () {
      final t = buildTreatmentTables([
        {
          'name': 'foffl', 'date': '2026-08-01', 'service': 'حشو عصب',
          'amount': 550, 'payment': 'تحويل',
          '_rateSnapshot': {'doctorPct': 30},
        },
        {
          'name': 'محمد علي', 'date': '2026-08-01',
          'service': 'دفعة دين — حشو عصب',
          'amount': 400, 'payment': 'تحويل',
          '_rateSnapshot': {'doctorPct': 30, 'treatmentId': 'حشو عصب'},
        },
      ], fallbackPct: 50);

      // مجموعة واحدة لا اثنتان (كان البلاغ).
      expect(t.groups, hasLength(1));
      final g = t.groups.single;
      expect(g.service, 'حشو عصب');
      expect(g.rows, hasLength(2));
      expect(g.revenue, 950);
      expect(g.doctor, 285); // 30% من 950
      expect(g.clinic, 665);
      expect(g.effPct, 30);
      // الإجمالي النهائي بلا أي تغيير رقمي.
      expect(t.revenue, 950);
      expect(t.doctor, 285);
      expect(t.clinic, 665);
    });
    test('دفعة أولى مجردة تنضم عبر اللقطة، والترتيب زمني داخل الجدول',
        () {
      final t = buildTreatmentTables([
        {
          'name': 'ب', 'date': '2026-08-02', 'service': 'خلع',
          'amount': 300, 'payment': 'كاش',
          '_rateSnapshot': {'doctorPct': 50, 'treatmentId': 'خلع'},
        },
        {
          'name': 'أ', 'date': '2026-08-01',
          'service': 'دفعة أولى (دين)',
          'amount': 100, 'payment': 'كاش',
          '_rateSnapshot': {'doctorPct': 50, 'treatmentId': 'خلع'},
        },
      ]);
      final g = t.groups.single;
      expect(g.service, 'خلع');
      expect([for (final r in g.rows) r.name], ['أ', 'ب']);
      expect(g.revenue, 400);
    });
  });
}
