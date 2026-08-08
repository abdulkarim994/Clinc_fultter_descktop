/// اختبارات م37 — شريط التبويبات بتصميم Vue الحرفي (nav-wrap/.tab-b):
///   • الشريط أبيض (لا داكن) والنشط بنقطة ذهبية 4px تحته (لا خط سفلي).
///   • أيقونات مخططة مخصصة (TabIcon) لا أيقونات Material ممتلئة.
///   • تبديل التبويب ينقل النقطة الذهبية.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/features/shell/tab_icons.dart';
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'staff_test_session.dart' show staffAdminSession;

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('m37_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> boot(WidgetTester tester) async {
    final c = ProviderContainer(
      overrides: [
        staffAdminSession(),
        dbDirProvider.overrideWithValue(tmp.path),
      ],
    );
    final auth = c.read(authServiceProvider);
    await auth.register('doc@clinic.ly', 'secret12');
    await auth.login('doc@clinic.ly', 'secret12', remember: true);
    c.read(reposProvider).settings.set('app.config', {
      'centerName': 'مركز الاختبار',
      'clinics': ['ع1'],
      'services': ['حشو'],
      'payments': ['كاش'],
    });
    c.dispose();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
        ],
        child: const DentalApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('الشريط أبيض والأيقونات مخططة والنقطة الذهبية تحت النشط', (
    tester,
  ) async {
    await boot(tester);

    // خمس أيقونات مخططة مخصصة (توأم SVG الأصل) — لا Material ممتلئة.
    expect(find.byType(TabIcon), findsNWidgets(5));

    // النشط الافتراضي «الرئيسية»: نقطته الذهبية ظاهرة.
    expect(find.byKey(const Key('tab-dot-home')), findsOneWidget);
    expect(find.byKey(const Key('tab-dot-clinics')), findsNothing);

    // الشريط أبيض: الحاوية الحاملة للصف بيضاء (--surface).
    final barBox = tester.widget<Container>(
      find
          .ancestor(
            of: find.byType(TabIcon).first,
            matching: find.byType(Container),
          )
          .last,
    );
    final deco = barBox.decoration;
    expect(
      deco is BoxDecoration && deco.color == Colors.white,
      isTrue,
      reason: 'خلفية الشريط بيضاء كالأصل لا داكنة',
    );

    // تبديل التبويب ينقل النقطة الذهبية.
    await tester.tap(find.text('السجلات'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('tab-dot-clinics')), findsOneWidget);
    expect(find.byKey(const Key('tab-dot-home')), findsNothing);

    // نص النشط أخضر عريض والخامل أخضر داكن شفاف (لوحة الأصل).
    final activeLbl = tester.widget<Text>(find.text('السجلات'));
    expect(activeLbl.style?.fontWeight, FontWeight.w800);
    expect(activeLbl.style?.color, const Color(0xFF1B5E47));
  });
}
