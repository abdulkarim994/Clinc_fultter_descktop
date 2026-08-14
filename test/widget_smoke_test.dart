/// اختبار شاشة الإثبات (م0) — تُقاد مباشرة بعد تحول جذر التطبيق إلى بوابة
/// الدخول في م3.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/features/proof/proof_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'staff_test_session.dart' show staffAdminSession;

void main() {
  testWidgets('Milestone-0 proof screen renders green', (tester) async {
    final tmp = Directory.systemTemp.createTempSync('m0_widget_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
        ],
        child: const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: ProofScreen(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('DENTSHINE'), findsOneWidget);
    // م133 — نظام الموظفين (م118) أضاف جدولي employees/expenses فصار
    // expectedTables خمسة عشر جدولاً لا ثلاثة عشر (schema_sql.dart). والمقام
    // في شاشة الإثبات صار مربوطاً بطول القائمة نفسها (expectedTableCount)
    // بدل «13» الثابتة التي كانت تعرض «15/13» — فالعدد يطابق المخطط دائماً.
    expect(find.textContaining('15/15'), findsOneWidget);
    expect(find.text('الميلستون صفر: كل الفحوصات ناجحة ✓'), findsOneWidget);
    expect(find.byIcon(Icons.cancel_rounded), findsNothing);
  });
}
