/// اختبارات م109 — صقل الواجهة: توسيط رقم شارة الدين الحمراء في قلب
/// الدائرة هندسياً (فارق المركزين ≤ 0.6 نقطة أفقياً وعمودياً).
library;

import 'package:dental_clinic_flutter/features/finance/finance_screen.dart'
    show PulseCountBadge;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('م109 — رقم الشارة في مركز الدائرة تماماً', (tester) async {
    for (final count in [3, 12]) {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(child: PulseCountBadge(count: count)),
        ),
      ));
      // نبضة الشارة رسم متكرر — إطارات محدودة لا pumpAndSettle.
      await tester.pump(const Duration(milliseconds: 120));

      final badge = tester.getRect(find.byType(PulseCountBadge));
      final text = tester.getRect(find.text('$count'));
      expect((text.center.dx - badge.center.dx).abs(), lessThan(0.6),
          reason: 'م109: توسيط أفقي تام ($count)');
      expect((text.center.dy - badge.center.dy).abs(), lessThan(0.6),
          reason: 'م109: توسيط عمودي تام ($count)');
      expect(badge.width, 22);
    }
  });
}
