/// م177 — إعادة تنظيم الحجز بالدور:
///   • ورقة الإضافة المنبثقة بسلسلة Enter (اسم ⇒ هاتف ⇒ ملاحظات ⇒ حفظ)
///     وتبقى مفتوحةً للتالي — وإلغاء زر + ومربع الإضافة العلوي نهائياً.
///   • شاشة اللوحة الكاملة: العيادة وسطاً بخط كبير، صف تاريخٍ بسهمين،
///     تبويبات «صباحاً/مساءً/الأرشيف» بمؤشرٍ منزلق.
///   • الحجز من بطاقة المريض يتحول تلقائياً للدور عند تفعيله.
///   • طبقة البيانات (quickAdd/م56) بلا مساس — الصف يُكتب بالمستودع.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/core/utils/js_compat.dart';
import 'package:dental_clinic_flutter/features/desktop/desktop_gate.dart';
import 'package:dental_clinic_flutter/features/queue/queue_screen.dart'
    show QueueBoardScreen, queueViewProvider;
import 'package:dental_clinic_flutter/features/records/record_saver.dart'
    hide JMap;
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'staff_test_session.dart' show staffAdminSession;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('m177_'));
  tearDown(() {
    debugForceDesktopUi = null;
    tmp.deleteSync(recursive: true);
  });

  Future<void> settle(WidgetTester t) async {
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
  }

  Future<ProviderContainer> bootShell(WidgetTester t,
      {void Function(ProviderContainer c)? seed}) async {
    debugForceDesktopUi = false;
    t.view.physicalSize = const Size(420, 1100);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final s = ProviderContainer(overrides: [
      staffAdminSession(),
      dbDirProvider.overrideWithValue(tmp.path),
    ]);
    final auth = s.read(authServiceProvider);
    await auth.register('doc@clinic.ly', 'secret12');
    await auth.login('doc@clinic.ly', 'secret12', remember: true);
    s.read(reposProvider).settings.set('app.config', {
      'centerName': 'م',
      'clinics': ['ع1'],
      'services': ['حشو'],
      'payments': ['كاش'],
      'bookingSystem': 'queue',
      'queueMorningStart': '10:00',
      'queueSlotMin': 20,
    });
    seed?.call(s);
    s.dispose();
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
        ],
        child: const DentalApp(),
      ),
    );
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    final ok = find.byKey(const Key('appt-notif-ok'));
    if (ok.evaluate().isNotEmpty) {
      await t.tap(ok);
      await t.pump(const Duration(milliseconds: 200));
    }
    return ProviderScope.containerOf(
      t.element(find.byType(DentalApp)),
      listen: false,
    );
  }

  Future<void> openBoard(WidgetTester t) async {
    await t.tap(find.text('الحجوزات'), warnIfMissed: false);
    await settle(t);
    await t.tap(find.byKey(const Key('clinic-ع1')), warnIfMissed: false);
    await t.pumpAndSettle();
  }

  group('م177 — لوحة الدور الكاملة', () {
    testWidgets('الترويسة والتبويبات المنزلقة وأسهم التاريخ — بلا مربع +',
        (t) async {
      final c = await bootShell(t);
      await openBoard(t);

      // الشاشة الكاملة: العيادة وسطاً بخط كبير والتاريخ الكبير بسهمين.
      expect(find.byKey(const Key('queue-clinic-title')), findsOneWidget);
      expect(find.byKey(const Key('queue-date-title')), findsOneWidget);
      expect(find.text('ع1'), findsOneWidget);
      // هيدر الصدفة مغطى (شاشة مستقلة).
      expect(find.text('متصل الآن'), findsNothing);
      // التبويبات الثلاثة الكبيرة.
      expect(find.byKey(const Key('period-morning')), findsOneWidget);
      expect(find.byKey(const Key('period-evening')), findsOneWidget);
      expect(find.byKey(const Key('period-archive')), findsOneWidget);
      // مربع + العلوي أُلغي نهائياً (قرار المالك).
      expect(find.byKey(const Key('queue-add-toggle')), findsNothing);

      // أسهم التاريخ تبدّل اليوم.
      final today = getCurrentDate();
      expect(c.read(queueViewProvider).date, today);
      await t.tap(find.byKey(const Key('queue-day-next')));
      await settle(t);
      expect(c.read(queueViewProvider).date.compareTo(today), 1);
      await t.tap(find.byKey(const Key('queue-day-prev')));
      await settle(t);
      expect(c.read(queueViewProvider).date, today);

      // التبويب ينزلق ويغير الفترة بالمزود.
      await t.tap(find.byKey(const Key('period-evening')));
      await t.pumpAndSettle();
      expect(c.read(queueViewProvider).period, 'evening');
      expect(t.takeException(), isNull);
    });

    testWidgets('سلسلة Enter: اسم ⇒ هاتف ⇒ ملاحظات ⇒ حفظ وتبقى مفتوحة',
        (t) async {
      final c = await bootShell(t);
      await openBoard(t);

      await t.tap(find.byKey(const Key('queue-fab-add')),
          warnIfMissed: false);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('queue-add-name')), findsOneWidget);

      // الاسم ثم Enter ⇒ التركيز ينتقل للهاتف.
      await t.enterText(find.byKey(const Key('queue-add-name')), 'سالم');
      await t.testTextInput.receiveAction(TextInputAction.next);
      await t.pumpAndSettle();
      expect(
          FocusScope.of(t.element(find.byKey(const Key('queue-add-phone'))))
              .focusedChild
              ?.context
              ?.widget,
          isNotNull);
      await t.enterText(
          find.byKey(const Key('queue-add-phone')), '0911111111');
      await t.testTextInput.receiveAction(TextInputAction.next);
      await t.pumpAndSettle();
      await t.enterText(
          find.byKey(const Key('queue-add-notes')), 'حالة مستعجلة');
      // آخر Enter (done) يحفظ — والنموذج يبقى مفتوحاً بحقولٍ مفرغة.
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pumpAndSettle();

      final rows = c
          .read(reposProvider)
          .queue
          .getByClinicDate('ع1', getCurrentDate());
      expect(rows, hasLength(1));
      expect(rows.single['patient_name'], 'سالم');
      expect(rows.single['phone'], '0911111111');
      expect(rows.single['notes'], 'حالة مستعجلة');
      expect(rows.single['est_time'], '10:00');
      // النموذج ما زال مفتوحاً بعدّاد «أُضيف 1».
      expect(find.byKey(const Key('queue-add-name')), findsOneWidget);
      expect(find.byKey(const Key('queue-add-count')), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });

  group('م177 — الحجز من بطاقة المريض (تبديل تلقائي)', () {
    testWidgets('نوع الحجز «بالدور» ⇒ لوحة الدور بورقةٍ معبأة',
        (t) async {
      await bootShell(t, seed: (s) {
        saveNewRecord(
          s.read(reposProvider),
          {'clinics': ['ع1'], 'services': ['حشو'], 'payments': ['كاش']},
          SaveRecordInput(
            name: 'هدى',
            date: getCurrentDate(),
            amount: 100,
            clinic: 'ع1',
            service: 'حشو',
            payment: 'كاش',
          ),
        );
      });
      // فتح بطاقة المريضة من السجلات.
      await t.tap(find.text('السجلات'), warnIfMissed: false);
      await settle(t);
      await t.enterText(find.byKey(const Key('patient-search')), 'هدى');
      await settle(t);
      await t.tap(find.byKey(const Key('patient-card-هدى')),
          warnIfMissed: false);
      await settle(t);
      await t.tap(find.byKey(const Key('psec-appts')), warnIfMissed: false);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('pp-fab-book')),
          warnIfMissed: false);
      await t.pumpAndSettle();

      // لوحة الدور فُتحت على عيادة المريضة وورقة الإضافة معبأة باسمها.
      expect(find.byType(QueueBoardScreen), findsOneWidget);
      expect(
          t
              .widget<TextField>(find.byKey(const Key('queue-add-name')))
              .controller!
              .text,
          'هدى');
      expect(t.takeException(), isNull);
    });
  });
}
