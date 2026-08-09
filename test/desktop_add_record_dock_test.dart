/// اختبارات لوح «زيارة جديدة» الجانبي (م146 — عقد التصميم «د»):
///   • Ctrl+N يضبط addRecordDockProvider فيظهر اللوح الجانبي العائم داخل
///     DesktopShell — مع AddRecordScreen بتخطيطه المقسّم.
///   • Esc وزر الإغلاق يغلقانه (يعيدان المزود إلى null).
///   • كل حقول النموذج (rec-*) موجودة بمفاتيح عقد «د» الحرفية.
///   • الدفع شريطٌ مقسّم: اختيار «دين» يكشف الدفعة الأولى وطريقتها —
///     **وإطار اللوح لا يتغير** (نقيض عقد «ج» الذي كان يقفز بين ارتفاعين).
///   • الحاسبة زرٌّ صغير داخل حقل القيمة نفسه.
///   • اللوح يطفو فوق مساحة العمل: الشِل والشريط الجانبي يبقيان ظاهرين،
///     واللوح لا يغطي كامل العرض.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/features/desktop/desktop_gate.dart';
import 'package:dental_clinic_flutter/features/desktop/desktop_shell.dart';
import 'package:dental_clinic_flutter/features/desktop/widgets/add_record_dock.dart';
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
  setUp(() => tmp = Directory.systemTemp.createTempSync('dock_'));
  tearDown(() {
    debugForceDesktopUi = null;
    tmp.deleteSync(recursive: true);
  });

  Future<void> boot(WidgetTester tester) async {
    debugForceDesktopUi = true;
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
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
      'services': ['حشو', 'قلع', 'تركيبات'],
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

  Future<void> sendCtrlN(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('Ctrl+N يفتح اللوح الجانبي بعنوان «زيارة جديدة»',
      (tester) async {
    await boot(tester);
    expect(find.byType(AddRecordSidePanel), findsNothing);
    await sendCtrlN(tester);
    expect(find.byType(AddRecordSidePanel), findsOneWidget);
    expect(find.byType(AddRecordScreen), findsOneWidget);
    expect(find.byKey(const Key('dock-title')), findsOneWidget);
    expect(find.text('زيارة جديدة'), findsWidgets);
  });

  testWidgets('Esc يغلق اللوح الجانبي', (tester) async {
    await boot(tester);
    await sendCtrlN(tester);
    expect(find.byType(AddRecordSidePanel), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(AddRecordSidePanel), findsNothing);
    expect(find.byType(AddRecordScreen), findsNothing);
  });

  testWidgets('زر إغلاق اللوح (dock-close) يغلقه', (tester) async {
    await boot(tester);
    await sendCtrlN(tester);
    expect(find.byType(AddRecordSidePanel), findsOneWidget);
    await tester.tap(find.byKey(const Key('dock-close')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(AddRecordSidePanel), findsNothing);
  });

  testWidgets('كل حقول عقد «د» موجودة داخل اللوح بمفاتيحها', (tester) async {
    await boot(tester);
    await sendCtrlN(tester);
    for (final k in [
      'rec-date',
      'rec-clinic',
      'rec-phone',
      'rec-name',
      'rec-service',
      'rec-amount',
      'rec-calc',
      'rec-payment-seg',
      'rec-report-open',
      'rec-medical-open',
      'rec-followup',
      'rec-notes',
      'rec-save',
      'rec-today',
    ]) {
      expect(find.byKey(Key(k)), findsOneWidget,
          reason: 'الحقل $k مفقود من لوح عقد «د»');
    }
    // مفاتيح عقد «ج» المستبدلة يجب ألا تعود للظهور في اللوح المكتبي.
    for (final gone in ['rec-payment', 'rec-debt', 'rec-report-tgl']) {
      expect(find.byKey(Key(gone)), findsNothing,
          reason: 'المفتاح القديم $gone عاد للظهور — عقد «د» استبدله');
    }
  });

  testWidgets('الحاسبة زرٌّ صغير داخل حقل القيمة نفسه', (tester) async {
    await boot(tester);
    await sendCtrlN(tester);
    final amountBox = tester.getRect(find.byKey(const Key('rec-amount')));
    final calcCenter = tester.getCenter(find.byKey(const Key('rec-calc')));
    expect(amountBox.contains(calcCenter), isTrue,
        reason: 'زر الحاسبة يجب أن يسكن داخل حدود حقل القيمة (suffix)');
  });

  testWidgets(
      'اختيار «دين» يكشف الدفعة الأولى وطريقتها — وإطار اللوح لا يتغير',
      (tester) async {
    await boot(tester);
    await sendCtrlN(tester);
    expect(find.byKey(const Key('rec-firstpay')), findsNothing);
    final frameBefore = tester.getRect(find.byType(AddRecordSidePanel));
    // اختر «دين» من الشريط المقسّم.
    await tester.tap(find.descendant(
      of: find.byKey(const Key('rec-payment-seg')),
      matching: find.text('دين'),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));
    // قسم الدين ظهر بحقليه.
    expect(find.byKey(const Key('rec-firstpay')), findsOneWidget);
    expect(find.byKey(const Key('rec-debtpay-seg')), findsOneWidget);
    // الإطار ثابت: لا قفز أبعادٍ بعد اليوم (جوهر عقد «د»).
    final frameAfter = tester.getRect(find.byType(AddRecordSidePanel));
    expect(frameAfter, equals(frameBefore),
        reason: 'توسعة الدين يجب أن تتحرك داخل اللوح لا أن تغيّر إطاره');
    // العودة إلى كاش تخفي القسم.
    await tester.tap(find.descendant(
      of: find.byKey(const Key('rec-payment-seg')),
      matching: find.text('كاش'),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));
    expect(find.byKey(const Key('rec-firstpay')), findsNothing);
  });

  testWidgets('اللوح يطفو فوق مساحة العمل ولا يحجب الشِل ولا الشريط الجانبي',
      (tester) async {
    await boot(tester);
    await sendCtrlN(tester);
    expect(find.byType(DesktopShell), findsOneWidget);
    // الشريط الجانبي (زر زيارة جديدة) ما يزال ظاهراً — اللوح لا يغطيه.
    expect(find.byKey(const Key('desk-new-visit')), findsOneWidget);
    // اللوح أسفل الهيدر وأضيق من الشاشة (جزء من الجدول يبقى مرئياً).
    final rect = tester.getRect(find.byType(AddRecordSidePanel));
    expect(rect.top, greaterThan(0));
    expect(rect.width, lessThan(700));
  });
}
