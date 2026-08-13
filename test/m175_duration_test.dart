/// م175 — مُصيغ المدة العربية (النص التلقائي بين أقدم وأحدث صورة):
/// مفرد/مثنى/جمع، سنوات مع أشهر، وحالات الحواف (تطابق/عكس/أصفار).
library;

import 'package:dental_clinic_flutter/features/xrays/compare_templates.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  int ts(int y, int m, [int d = 1]) =>
      DateTime(y, m, d).millisecondsSinceEpoch;

  test('أيام وشهور وسنوات بصيغ عربية سليمة', () {
    expect(arDurationBetween(ts(2026, 1, 1), ts(2026, 1, 2)), 'يوم');
    expect(arDurationBetween(ts(2026, 1, 1), ts(2026, 1, 3)), 'يومين');
    expect(arDurationBetween(ts(2026, 1, 1), ts(2026, 1, 6)), '5 أيام');
    expect(arDurationBetween(ts(2026, 1, 1), ts(2026, 1, 21)), '20 يوماً');
    expect(arDurationBetween(ts(2026, 1, 1), ts(2026, 2, 1)), 'شهر');
    expect(arDurationBetween(ts(2026, 1, 1), ts(2026, 3, 1)), 'شهرين');
    expect(arDurationBetween(ts(2026, 1, 1), ts(2026, 7, 1)), '6 أشهر');
    expect(arDurationBetween(ts(2025, 1, 1), ts(2026, 1, 1)), 'سنة');
    expect(arDurationBetween(ts(2024, 1, 1), ts(2026, 1, 1)), 'سنتين');
    expect(arDurationBetween(ts(2020, 1, 1), ts(2026, 1, 1)), '6 سنوات');
    expect(
        arDurationBetween(ts(2025, 1, 1), ts(2026, 3, 1)), 'سنة وشهرين');
  });

  test('حالات الحواف: تطابق/عكس/أصفار ⇒ فارغة', () {
    expect(arDurationBetween(ts(2026, 1, 1), ts(2026, 1, 1)), '');
    expect(arDurationBetween(ts(2026, 2, 1), ts(2026, 1, 1)), '');
    expect(arDurationBetween(0, ts(2026, 1, 1)), '');
    expect(arDurationBetween(ts(2026, 1, 1), 0), '');
  });

  test('جملة المتابعة الجاهزة', () {
    expect(followUpSentence(ts(2020, 1, 1), ts(2026, 1, 1)),
        'متابعة الحالة بعد 6 سنوات من العلاج');
    expect(followUpSentence(0, 0), '');
  });

  test('قوالب العائلتين: 4+4 ومعرفات فريدة', () {
    expect(templatesOf('smile').length, 4);
    expect(templatesOf('xray').length, 4);
    final ids = {for (final t in kCompareTemplates) t.id};
    expect(ids.length, kCompareTemplates.length);
  });
}
