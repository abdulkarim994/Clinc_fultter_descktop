/// اختبارات م38 — نسب المعالجات في طباعة الكاش/التحويل (تفصيل الخزينة):
/// كان الجدول مسطحاً بلا نسب؛ الأصل (TreasuryTab) يجمّع بالمعالجة عبر
/// buildTreatmentTables: رأس «نسبة الطبيب X% • نسبة العيادة Y%» وعمودا
/// طبيب/عيادة والانهيار 0% والإجمالي النهائي — نختبر البنية والحساب.
library;

import 'package:dental_clinic_flutter/features/print/treatment_tables.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('التجميع بالمعالجة مع نسبة اللقطة المجمّدة وعمودي طبيب/عيادة', () {
    final t = buildTreatmentTables([
      {
        'name': 'سالم', 'date': '2026-07-01', 'service': 'حشو',
        'amount': 100, 'payment': 'كاش',
        '_rateSnapshot': {'doctorPct': 40},
      },
      {
        'name': 'هدى', 'date': '2026-07-02', 'service': 'حشو',
        'amount': 300, 'payment': 'تحويل',
        '_rateSnapshot': {'doctorPct': 40},
      },
      {
        'name': 'وليد', 'date': '2026-07-03', 'service': 'تنظيف',
        'amount': 200, 'payment': 'كاش',
        // بلا لقطة ⇒ fallback (نسبة الإعدادات العامة).
      },
    ], fallbackPct: 50);

    expect(t.groups, hasLength(2));
    final fill = t.groups.firstWhere((g) => g.service == 'حشو');
    expect(fill.zeroPct, isFalse, reason: 'النسبة يجب أن تظهر لا تنهار');
    expect(fill.effPct, 40);
    expect(fill.revenue, 400);
    expect(fill.doctor, 160, reason: '40% من 400');
    expect(fill.clinic, 240);
    // صفوف المجموعة مرتبة بالتاريخ صعوداً وبحصص محسوبة.
    expect(fill.rows.first.name, 'سالم');
    expect(fill.rows.first.doctor, 40);
    expect(fill.rows.first.clinic, 60);

    final clean = t.groups.firstWhere((g) => g.service == 'تنظيف');
    expect(clean.effPct, 50, reason: 'fallback نسبة الإعدادات');
    expect(clean.doctor, 100);

    // الإجمالي النهائي (الإيرادات/ربح الطبيب/ربح العيادة).
    expect(t.revenue, 600);
    expect(t.doctor, 260);
    expect(t.clinic, 340);
  });

  test('نسبة 0% تنهار لجدول الإيرادات فقط (توأم الأصل)', () {
    final t = buildTreatmentTables([
      {
        'name': 'أ', 'date': '2026-07-01', 'service': 'كشف',
        'amount': 50, 'payment': 'كاش',
        '_rateSnapshot': {'doctorPct': 0},
      },
    ], fallbackPct: 50);
    expect(t.groups.single.zeroPct, isTrue);
    expect(t.groups.single.revenue, 50);
    expect(t.doctor, 0);
  });

  test('لقطة نصية (سجلات Vue قديمة) لا تكسر النسبة', () {
    // بعض الصفوف القديمة تحمل اللقطة أرقاماً نصية.
    final t = buildTreatmentTables([
      {
        'name': 'ب', 'date': '2026-07-01', 'service': 'تقويم',
        'amount': 1000, 'payment': 'كاش',
        '_rateSnapshot': {'doctorPct': '35'},
      },
    ], fallbackPct: 50);
    expect(t.groups.single.effPct, 35);
    expect(t.groups.single.doctor, 350);
  });
}
