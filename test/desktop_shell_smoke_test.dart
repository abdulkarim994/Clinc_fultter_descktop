/// اختبارات صدفة سطح المكتب — البوابة والشريط الجانبي:
///   • البوابة: منصة سطح مكتب + عرض ≥ 1100 ⇒ DesktopShell؛ وعرض أضيق أو
///     منصة هاتف ⇒ تخطيط الهاتف الحالي حرفياً (لا تبويب خزينة مستقلاً).
///   • الشريط الجانبي: التبويبات الثمانية بالترتيب الجديد المعتمد،
///     والطي/التمدد يعمل ويُحفظ، وتبديل التبويب يبدّل المحتوى بلا صفحات.
///   • «زيارة جديدة» تفتح درجاً جانبياً (نموذج AddRecordScreen) لا ورقة.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/features/desktop/desktop_gate.dart';
import 'package:dental_clinic_flutter/features/desktop/desktop_shell.dart';
import 'package:dental_clinic_flutter/features/records/add_record_screen.dart'
    show AddRecordScreen;
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'staff_test_session.dart' show staffAdminSession;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('desk_'));
  tearDown(() {
    debugForceDesktopUi = null;
    tmp.deleteSync(recursive: true);
  });

  Future<void> boot(WidgetTester tester, {required bool desktop}) async {
    debugForceDesktopUi = desktop;
    if (desktop) {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }
    final c = ProviderContainer(overrides: [
      staffAdminSession(),
      dbDirProvider.overrideWithValue(tmp.path),
    ]);
    final auth = c.read(authServiceProvider);
    await auth.register('doc@clinic.ly', 'secret12');
    await auth.login('doc@clinic.ly', 'secret12', remember: true);
    c.read(reposProvider).settings.set('app.config', {
      'centerName': 'مركز الاختبار',
      'clinics': ['ع1'],
      'services': ['حشو', 'قلع'],
      'payments': ['كاش', 'تحويل'],
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

  testWidgets('البوابة: سطح المكتب يعرض DesktopShell بتبويبات الترتيب الجديد',
      (tester) async {
    await boot(tester, desktop: true);
    expect(find.byType(DesktopShell), findsOneWidget);
    // الترتيب الجديد الثماني.
    for (final id in [
      'home',
      'clinics',
      'finance',
      'treasury',
      'debts',
      'expenses',
      'extra',
      'calendar',
    ]) {
      expect(find.byKey(Key('desk-tab-$id')), findsOneWidget,
          reason: 'تبويب $id مفقود من الشريط الجانبي');
    }
    // تسميات القرار: الخزينة والديون والمصروفات تبويبات مباشرة.
    expect(find.text('الخزينة'), findsOneWidget);
    expect(find.text('الديون'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('desk-tab-expenses')),
        matching: find.text('المصروفات'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('البوابة: الهاتف يبقى على تخطيطه الحالي حرفياً',
      (tester) async {
    await boot(tester, desktop: false);
    expect(find.byType(DesktopShell), findsNothing);
    // شريط الهاتف: 5 تبويبات — لا تبويب «الخزينة» مستقلاً.
    expect(find.text('الرئيسية'), findsOneWidget);
    expect(find.text('المالية'), findsOneWidget);
    expect(find.text('الخزينة'), findsNothing);
    expect(find.byKey(const Key('desk-new-visit')), findsNothing);
  });

  testWidgets('تبديل التبويب يبدّل المحتوى فقط (خزينة/ديون) بلا صفحات',
      (tester) async {
    await boot(tester, desktop: true);
    await tester.tap(find.byKey(const Key('desk-tab-treasury')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(DesktopShell), findsOneWidget);
    await tester.tap(find.byKey(const Key('desk-tab-debts')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(DesktopShell), findsOneWidget);
    await tester.tap(find.byKey(const Key('desk-tab-home')));
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('طي الشريط الجانبي يعمل ويخفي التسميات', (tester) async {
    await boot(tester, desktop: true);
    expect(find.text('السجلات'), findsOneWidget);
    await tester.tap(find.byKey(const Key('desk-sidebar-collapse')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('السجلات'), findsNothing,
        reason: 'التسميات تختفي في وضع الطي (أيقونات فقط)');
    await tester.tap(find.byKey(const Key('desk-sidebar-collapse')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('السجلات'), findsOneWidget);
  });

  testWidgets('«زيارة جديدة» تفتح النموذج الكامل درجاً جانبياً',
      (tester) async {
    await boot(tester, desktop: true);
    await tester.tap(find.byKey(const Key('desk-new-visit')));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(AddRecordScreen), findsOneWidget);
    // Esc يغلق الدرج (اختصار سطح المكتب).
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(AddRecordScreen), findsNothing);
  });
}
