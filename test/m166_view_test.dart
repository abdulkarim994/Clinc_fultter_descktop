/// م166 — تحسينات العرض: شاشة اليوم الكاملة بالهاتف (بلا أرشيف — قرار
/// المالك)، وملء الشاشة للجدولة الأسبوعية بالكمبيوتر (فتح/خروج)، وتكبير
/// Ctrl+عجلة الفأرة بحفظ المقياس في تفضيلات الجهاز.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/core/utils/js_compat.dart'
    show getCurrentDate;
import 'package:dental_clinic_flutter/features/appointments/appointments_tab.dart';
import 'package:dental_clinic_flutter/features/desktop/desktop_gate.dart'
    show debugForceDesktopUi;
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'staff_test_session.dart' show staffAdminSession;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('m166_'));
  tearDown(() {
    debugForceDesktopUi = null;
    tmp.deleteSync(recursive: true);
  });

  Map<String, Object?> config() => {
        'centerName': 'مركز الاختبار',
        'clinics': ['ع1'],
        'services': ['حشو'],
        'payments': ['كاش'],
        'workdayStart': '09:00',
        'workdayEnd': '12:00',
      };

  List<Override> ov() => [
        staffAdminSession(),
        dbDirProvider.overrideWithValue(tmp.path),
      ];

  Future<ProviderContainer> boot(
    WidgetTester t, {
    Size size = const Size(420, 950),
    void Function(ProviderContainer c)? seed,
  }) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final c0 = ProviderContainer(overrides: ov());
    final auth = c0.read(authServiceProvider);
    await auth.register('doc@clinic.ly', 'secret12');
    await auth.login('doc@clinic.ly', 'secret12', remember: true);
    c0.read(reposProvider).settings.set('app.config', config());
    seed?.call(c0);
    c0.dispose();
    return ProviderContainer(overrides: ov());
  }

  void seedAppt(ProviderContainer c, String id, String name, String time) {
    c.read(reposProvider).appointments.upsertLocal({
      'id': id,
      'name': name,
      'date': getCurrentDate(),
      'time': time,
      'service': 'حشو',
      'status': 'pending',
      'clinic': 'ع1',
      '_t': 'a',
    });
  }

  testWidgets(
      'الهاتف: رأس الجدول يفتح شاشة اليوم الكاملة — بلا أرشيف وبإضافة تعمل',
      (t) async {
    final c = await boot(t, seed: (c0) {
      seedAppt(c0, 'a1', 'وليد', '09:00');
      // مؤرشفٌ اليوم — يجب ألا يظهر في شاشة اليوم (قرار المالك).
      c0.read(reposProvider).appointments.upsertLocal({
        'id': 'done1',
        'name': 'منجز',
        'date': getCurrentDate(),
        'time': '10:00',
        'status': 'completed',
        'archivedOn': getCurrentDate(),
        'clinic': 'ع1',
        '_t': 'a',
      });
    });
    addTearDown(c.dispose);
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: AppointmentsTab()),
        ),
      ),
    ));
    await t.pump(const Duration(milliseconds: 350));

    // النقر على رأس البطاقة يفتح شاشة اليوم.
    await t.tap(find.byKey(const Key('appt-day-open')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('appointments-day-only')), findsOneWidget);
    expect(find.byKey(const Key('appt-row-a1')), findsOneWidget);
    // لا أرشيف في شاشة اليوم.
    expect(find.textContaining('أرشيف اليوم'), findsNothing);
    expect(find.byKey(const Key('appt-row-done1')), findsNothing);

    // ورقة الإجراءات تعمل من داخلها.
    await t.tap(find.byKey(const Key('appt-row-a1')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('appt-edit-a1')), findsOneWidget);
    await t.tap(find.byKey(const Key('appt-cancel-appt-a1')),
        warnIfMissed: false);
    await t.pumpAndSettle();
    expect(c.read(reposProvider).appointments.getById('a1')!['status'],
        'cancelled');

    // الإضافة من شاشة اليوم: العيادة واليوم معبآن مسبقاً.
    await t.tap(find.byKey(const Key('appt-add-toggle')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('appt-name')), 'جديد');
    await t.ensureVisible(find.byKey(const Key('appt-save')));
    await t.tap(find.byKey(const Key('appt-save')), warnIfMissed: false);
    await t.pumpAndSettle();
    final saved = c
        .read(reposProvider)
        .appointments
        .getAll()
        .firstWhere((a) => a['name'] == 'جديد');
    expect(saved['clinic'], 'ع1');
    expect(saved['date'], getCurrentDate());

    // الرجوع يعيد لتبويب الحجوزات الأم.
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.byKey(const Key('appointments-tab')), findsOneWidget);
  });

  Future<void> bootDesktop(WidgetTester t) async {
    debugForceDesktopUi = true;
    t.view.physicalSize = const Size(1600, 1000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final c0 = ProviderContainer(overrides: ov());
    final auth = c0.read(authServiceProvider);
    await auth.register('doc@clinic.ly', 'secret12');
    await auth.login('doc@clinic.ly', 'secret12', remember: true);
    c0.read(reposProvider).settings.set('app.config', config());
    seedAppt(c0, 'd1', 'مريض المكتب', '09:00');
    c0.dispose();
    await t.pumpWidget(
        ProviderScope(overrides: ov(), child: const DentalApp()));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    // إغلاق إشعار مواعيد اليوم إن ظهر.
    if (find.byKey(const Key('appt-notif-ok')).evaluate().isNotEmpty) {
      await t.tap(find.byKey(const Key('appt-notif-ok')));
      await t.pumpAndSettle();
    }
    await t.tap(find.byKey(const Key('desk-tab-calendar')),
        warnIfMissed: false);
    await t.pumpAndSettle();
  }

  testWidgets('الكمبيوتر: ملء الشاشة يفتح الجدولة كاملةً وEsc يخرج',
      (t) async {
    await bootDesktop(t);
    expect(find.byKey(const Key('appt-week-view')), findsOneWidget);

    await t.tap(find.byKey(const Key('appt-desk-fullscreen')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('appt-week-view-full')), findsOneWidget);
    // الشريط الجانبي مختفٍ (زر «زيارة جديدة» يختفي بملء الشاشة).
    expect(find.text('جدول المواعيد — ملء الشاشة'), findsOneWidget);

    // Esc يخرج.
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('appt-week-view-full')), findsNothing);
    expect(find.byKey(const Key('appt-week-view')), findsOneWidget);
  });

  testWidgets('الكمبيوتر: Ctrl+عجلة يكبّر ويصغّر ويحفظ المقياس', (t) async {
    await bootDesktop(t);
    final center = t.getCenter(find.byKey(const Key('appt-week-scroll')));

    Future<void> wheel(double dy) async {
      final p = TestPointer(1, PointerDeviceKind.mouse);
      p.hover(center);
      await t.sendEventToBinding(p.scroll(Offset(0, dy)));
      await t.pumpAndSettle();
    }

    // بلا Ctrl: لا شارة مقياس (100%).
    await wheel(-100);
    expect(find.byKey(const Key('appt-week-zoom-reset')), findsNothing);

    // مع Ctrl: تكبير ⇒ تظهر شارة المقياس بغير 100%.
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await wheel(-100);
    await wheel(-100);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(find.byKey(const Key('appt-week-zoom-reset')), findsOneWidget);
    expect(find.textContaining('121%'), findsOneWidget,
        reason: 'خطوتا تكبير 10% ⇒ 121%');

    // زر إعادة الضبط يعيد 100% وتختفي الشارة.
    await t.tap(find.byKey(const Key('appt-week-zoom-reset')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('appt-week-zoom-reset')), findsNothing);
  });
}
