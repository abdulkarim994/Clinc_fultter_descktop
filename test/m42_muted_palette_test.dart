/// اختبار م42 — لوحة النصوص الباهتة بتباين مرجع الأصل:
/// النص الثانوي في Vue بعتامة 72% من الحبر (rgba(15,42,32,.72))
/// وplaceholder بعتامة 50% — اللوحة القديمة (54/45/38%) كانت أفتح.
library;

import 'package:dental_clinic_flutter/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => BrandColors.darkMode = false);

  test('الوضع الفاتح: mut/mut2/faint على درجات الحبر المرجعية', () {
    BrandColors.darkMode = false;
    expect(BrandColors.mut, const Color.fromRGBO(15, 42, 32, .72),
        reason: 'الثانوي = مرجع Vue ‏72%');
    expect(BrandColors.mut2, const Color.fromRGBO(15, 42, 32, .62));
    expect(BrandColors.faint, const Color.fromRGBO(15, 42, 32, .50));
    // أوضح فعلاً من اللوحة القديمة (54/45/38%).
    expect(BrandColors.mut.a, greaterThan(0.54));
    expect(BrandColors.mut2.a, greaterThan(0.45));
    expect(BrandColors.faint.a, greaterThan(0.38));
  });

  test('الوضع الداكن: عتامات موازية أوضح', () {
    BrandColors.darkMode = true;
    expect(BrandColors.mut.a, greaterThan(0.75));
    expect(BrandColors.mut2.a, greaterThan(0.6));
    expect(BrandColors.faint.a, greaterThanOrEqualTo(0.5));
  });
}
