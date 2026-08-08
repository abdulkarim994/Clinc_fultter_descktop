/// اختبارات م139 (المرحلة د) — مساعد تسمية التخزين في مقارنة الباقات.
library;

import 'package:dental_clinic_flutter/features/settings/subscription_section.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('م139 — mbLabelAr', () {
    test('صفر/سالب ⇒ رمز اللانهاية (بلا حدّ)', () {
      expect(mbLabelAr(0), '∞');
      expect(mbLabelAr(-5), '∞');
    });
    test('ميغابايت ثم غيغابايت', () {
      expect(mbLabelAr(200), '200 م.ب');
      expect(mbLabelAr(1024), '1 غ.ب');
      expect(mbLabelAr(1536), '1.5 غ.ب');
      expect(mbLabelAr(10240), '10 غ.ب');
    });
  });
}
