/// اختبارات لوح «زيارة جديدة» المرسى (Desktop Bottom Dock):
///   • Ctrl+N يضبط addRecordDockProvider فيظهر اللوح المرسى داخل DesktopShell
///     (لا حوارٌ ولا درجٌ منزلق) — مع AddRecordScreen بتخطيطه الأفقي.
///   • Esc يغلقه (يعيد المزود إلى null).
///   • كل حقول النموذج (rec-*) موجودة داخل اللوح بمفاتيحها الحرفية.
///   • تفعيل «دين» يوسّع اللوح تلقائياً (يظهر قسم الدفعة الأولى ويرتفع اللوح).
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

  testWidgets('Ctrl+N يفتح اللوح المرسى (لا درج) بعنوان «زيارة جديدة»',
      (tester) async {
    await boot(tester);
    // لا لوح قبل الفتح.
    expect(find.byType(AddRecordDock), findsNothing);
    await sendCtrlN(tester);
    // اللوح ظهر داخل الشِل مع النموذج.
    expect(find.byType(AddRecordDock), findsOneWidget);
    expect(find.byType(AddRecordScreen), findsOneWidget);
    expect(find.byKey(const Key('dock-title')), findsOneWidget);
    expect(find.text('زيارة جديدة'), findsWidgets);
  });

  testWidgets('Esc يغلق اللوح المرسى', (tester) async {
    await boot(tester);
    await sendCtrlN(tester);
    expect(find.byType(AddRecordDock), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(AddRecordDock), findsNothing);
    expect(find.byType(AddRecordScreen), findsNothing);
  });

  testWidgets('زر إغلاق اللوح (dock-close) يغلقه', (tester) async {
    await boot(tester);
    await sendCtrlN(tester);
    expect(find.byType(AddRecordDock), findsOneWidget);
    await tester.tap(find.byKey(const Key('dock-close')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(AddRecordDock), findsNothing);
  });

  testWidgets('كل حقول النموذج موجودة داخل اللوح (تخطيط أفقي)',
      (tester) async {
    await boot(tester);
    await sendCtrlN(tester);
    for (final k in [
      'rec-date',
      'rec-clinic',
      'rec-phone',
      'rec-name',
      'rec-service',
      'rec-payment',
      'rec-amount',
      'rec-debt',
      'rec-followup',
      'rec-report-tgl',
      'rec-medical-tgl',
      'rec-notes',
      'rec-save',
      'rec-calc',
      'rec-today',
    ]) {
      expect(find.byKey(Key(k)), findsOneWidget,
          reason: 'الحقل $k مفقود من اللوح الأفقي');
    }
  });

  testWidgets('تفعيل «دين» يوسّع اللوح ويُظهر قسم الدفعة الأولى',
      (tester) async {
    await boot(tester);
    await sendCtrlN(tester);
    // قبل التفعيل: لا قسم دين، ونقيس ارتفاع اللوح المضغوط.
    expect(find.byKey(const Key('rec-firstpay')), findsNothing);
    final compactH =
        tester.getSize(find.byType(AddRecordDock)).height;
    // فعّل مفتاح الدين.
    await tester.tap(find.byKey(const Key('rec-debt')));
    await tester.pump(); // بناء النموذج بـ isDebt=true + جدولة إشعار التوسّع.
    await tester.pump(); // تنفيذ postFrame + setState على اللوح.
    await tester.pump(const Duration(milliseconds: 260)); // اكتمال الانتقال.
    // قسم الدفعة الأولى ظهر، واللوح توسّع.
    expect(find.byKey(const Key('rec-firstpay')), findsOneWidget);
    final expandedH =
        tester.getSize(find.byType(AddRecordDock)).height;
    expect(expandedH, greaterThan(compactH),
        reason: 'تفعيل الدين يجب أن يوسّع اللوح تلقائياً');
  });

  testWidgets('اللوح يعيش أسفل مساحة العمل داخل الشِل (لا فوقها)',
      (tester) async {
    await boot(tester);
    await sendCtrlN(tester);
    // الشِل باقٍ ظاهراً تحت اللوح (اللوح ليس حواراً يغطي كل شيء).
    expect(find.byType(DesktopShell), findsOneWidget);
    // الشريط الجانبي (زر زيارة جديدة) ما يزال ظاهراً.
    expect(find.byKey(const Key('desk-new-visit')), findsOneWidget);
    // اللوح أسفل الهيدر: أعلى اللوح أدنى من أعلى الشاشة.
    final dockTop = tester.getTopLeft(find.byType(AddRecordDock)).dy;
    expect(dockTop, greaterThan(0));
  });
}
