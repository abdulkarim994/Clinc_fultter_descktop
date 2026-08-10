/// م161 — منطق قسم المختبر الجديد: قيمة المختبر الشهرية (تصفر مطلع
/// الشهر)، صفوف الجدول مرتبة بالأحدث، والقيمة = قيمة المختبر (labValue).
library;

import 'package:dental_clinic_flutter/features/labs/labs_logic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final pros = <Map<String, Object?>>[
    {
      'id': 'a',
      'labName': 'النور',
      'date': '2026-08-03',
      'name': 'محمد',
      'clinic': 'ع1',
      'prosType': 'زيركون',
      'prosUnits': 3,
      'labValue': 300,
      'total': 1500,
    },
    {
      'id': 'b',
      'labName': 'النور',
      'date': '2026-08-10',
      'name': 'خالد',
      'clinic': 'ع2',
      'prosType': 'ببك',
      'prosUnits': 2,
      'labValue': 500,
      'total': 2000,
    },
    {
      'id': 'c',
      'labName': 'النور',
      'date': '2026-07-20',
      'name': 'سالم',
      'clinic': 'ع1',
      'prosType': 'ببك',
      'prosUnits': 1,
      'labValue': 250,
      'total': 900,
    },
    {
      'id': 'd',
      'labName': 'الفجر',
      'date': '2026-08-05',
      'name': 'ليلى',
      'clinic': 'ع1',
      'prosType': 'زيركون',
      'prosUnits': 4,
      'labValue': 700,
      'total': 3000,
    },
  ];

  test('صفوف مختبر الشهر مرتبة بالأحدث أولاً والقيمة = labValue', () {
    final rows = labMonthRows('النور', prosthetics: pros, month: '2026-08');
    expect(rows.length, 2, reason: 'حالتا أغسطس فقط لمختبر النور');
    expect(rows.first.date, '2026-08-10', reason: 'الأحدث أولاً');
    expect(rows.last.date, '2026-08-03');
    expect(rows.first.value, 500, reason: 'القيمة = قيمة المختبر');
    expect(rows.first.units, 2);
    expect(rows.first.clinic, 'ع2');
  });

  test('قيمة المختبر الشهرية تجمع labValue لحالات الشهر وتصفر بتغيّره', () {
    expect(labMonthValue('النور', prosthetics: pros, month: '2026-08'), 800);
    expect(labMonthValue('النور', prosthetics: pros, month: '2026-07'), 250);
    expect(labMonthValue('النور', prosthetics: pros, month: '2026-09'), 0,
        reason: 'شهر بلا حالات = صفر (التصفير الشهري)');
  });

  test('بطاقات المختبرات لشهرٍ مختار بقيمها وعددها مرتبةً أبجدياً', () {
    final cards =
        labCards(['النور', 'الفجر'], prosthetics: pros, month: '2026-08');
    expect(cards.map((c) => c.name).toList(), ['الفجر', 'النور']);
    final noor = cards.firstWhere((c) => c.name == 'النور');
    expect(noor.monthValue, 800);
    expect(noor.count, 2);
    final fajr = cards.firstWhere((c) => c.name == 'الفجر');
    expect(fajr.monthValue, 700);
    expect(fajr.count, 1);
  });

  test('تجميع صفوف المختبر بالعيادة لخيار الطباعة', () {
    final rows = labMonthRows('النور', prosthetics: pros, month: '2026-08');
    final byClinic = labRowsByClinic(rows);
    expect(byClinic.keys.toSet(), {'ع1', 'ع2'});
    expect(byClinic['ع2']!.single.name, 'خالد');
  });
}
