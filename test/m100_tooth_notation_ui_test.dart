/// اختبارات م100 (واجهة) — حوار الأسنان يعرض الرمز الصحيح حسب النظام:
/// FDI رقمان («16») وPalmer الموضع مع إطار ربعي («6»). الحوار خالٍ من
/// ريفربود فلا يحتاج قاعدة بيانات — سريعٌ وحاسم.
library;

import 'package:dental_clinic_flutter/features/records/tooth_label_widget.dart';
import 'package:dental_clinic_flutter/features/records/tooth_notation.dart';
import 'package:dental_clinic_flutter/features/records/tooth_report_dialog.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> openDialog(WidgetTester tester, NotationSystem system) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ar'),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showToothReportDialog(
              context,
              teethOnly: true,
              entries: [
                {
                  'id': 'r1',
                  'service': 'علاج',
                  'cost': 0,
                  'teeth': [
                    {'q': 'UR', 'n': 6},
                  ],
                },
              ],
              notation: system,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('FDI: السن UR:6 يظهر «16» بلا إطار ربعي', (tester) async {
    await openDialog(tester, NotationSystem.fdi);
    expect(find.byKey(const Key('tr-sel-UR:6')), findsOneWidget);
    expect(find.text('16'), findsWidgets);
    expect(find.text('6'), findsNothing);
    // لا إطار Palmer في وضع FDI.
    final view = tester.widget<ToothLabelView>(
        find.descendant(
            of: find.byKey(const Key('tr-sel-UR:6')),
            matching: find.byType(ToothLabelView)));
    expect(view.label.palmerBorder, isFalse);
  });

  testWidgets('Palmer: السن UR:6 يظهر «6» مع إطار ربعي', (tester) async {
    await openDialog(tester, NotationSystem.palmer);
    expect(find.byKey(const Key('tr-sel-UR:6')), findsOneWidget);
    expect(find.text('6'), findsWidgets);
    expect(find.text('16'), findsNothing);
    final view = tester.widget<ToothLabelView>(
        find.descendant(
            of: find.byKey(const Key('tr-sel-UR:6')),
            matching: find.byType(ToothLabelView)));
    expect(view.label.palmerBorder, isTrue,
        reason: 'م100: Palmer يرسم إطار الربع');
    expect(view.label.quadrant, 'UR');
  });
}
