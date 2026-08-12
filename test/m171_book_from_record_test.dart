/// م171 — حجز موعد من سجل المريض + مربع المواعيد في البطاقة:
///   • patientUpcomingAppointments: ترشيح بالاسم (واستبعاد السميّ بهاتفين
///     صريحين مختلفين)، استثناء الاستراحات والنهائية، ترتيب تاريخ/وقت.
///   • بطاقة المريض: تبويب «المواعيد» بين الديون والأشعة بعدّاده، صفوفه
///     تعرض الموعد، والنقر يبذر يوم الهبوط ويفتح تبويب المواعيد.
///   • «حجز موعد» من ورقة إجراءات البطاقة يبذر مسودة الحجز.
///   • الكمبيوتر: مسودة الحجز تفتح نموذج «موعد جديد» معبأً، ويوم الهبوط
///     يبدأ الجدول الأسبوعي منه.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/features/appointments/appointments_tab.dart'
    show apptBookDraftProvider, apptGoDayProvider;
import 'package:dental_clinic_flutter/features/appointments/appt_lifecycle.dart'
    show patientUpcomingAppointments;
import 'package:dental_clinic_flutter/features/desktop/desktop_gate.dart';
import 'package:dental_clinic_flutter/features/patients/patient_profile_screen.dart'
    hide JMap;
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'staff_test_session.dart' show staffAdminSession;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('m171_'));
  tearDown(() {
    debugForceDesktopUi = null;
    tmp.deleteSync(recursive: true);
  });

  String ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  DateTime day0() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  group('م171 — patientUpcomingAppointments (نقية)', () {
    test('ترشيح واستبعاد وترتيب', () {
      final rows = <Map<String, Object?>>[
        // موعدا المريض (غير مرتبين عمداً).
        {'id': 'b', 'name': 'سالم', 'date': '2026-09-01', 'time': '10:00',
          'status': 'pending'},
        {'id': 'a', 'name': 'سالم', 'date': '2026-08-20', 'time': '09:00',
          'status': 'upcoming'},
        // سميٌّ بهاتفٍ صريحٍ مختلف ⇒ يُستبعد.
        {'id': 'x', 'name': 'سالم', 'phone': '0999999999',
          'date': '2026-08-25', 'time': '11:00', 'status': 'pending'},
        // استراحة وحالة نهائية ⇒ تُستبعدان.
        {'id': 'brk', 'name': 'استراحة', 'date': '2026-08-21',
          'isBreak': 1, 'status': 'pending'},
        {'id': 'done', 'name': 'سالم', 'date': '2026-08-22',
          'status': 'completed'},
        // اسمٌ آخر ⇒ يُستبعد.
        {'id': 'other', 'name': 'هدى', 'date': '2026-08-23',
          'status': 'pending'},
      ];
      final out =
          patientUpcomingAppointments(rows, 'سالم', phone: '0911111111');
      expect([for (final a in out) a['id']], ['a', 'b'],
          reason: 'مرتبة تصاعدياً، بلا السميّ والاستراحة والمكتمل');
      // بلا هاتفٍ للملف: صف الهاتف الصريح يدخل (لا استبعاد احتياطياً).
      final all = patientUpcomingAppointments(rows, 'سالم');
      expect(all.length, 3);
    });
  });

  Future<ProviderContainer> bootPhoneProfile(WidgetTester tester) async {
    debugForceDesktopUi = false;
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
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
      'payments': ['كاش', 'تحويل'],
    });
    final repos = s.read(reposProvider);
    repos.records.upsertLocal({
      'id': 'r1',
      'name': 'سالم المريض',
      'date': ymd(day0()),
      'amount': 100,
      'paid': 100,
      'payment': 'كاش',
      'clinic': 'ع1',
      '_t': 'r',
    });
    repos.appointments.upsertLocal({
      'id': 'fut1',
      'name': 'سالم المريض',
      'date': ymd(day0().add(const Duration(days: 5))),
      'time': '10:30',
      'clinic': 'ع1',
      'status': 'pending',
      '_t': 'a',
    });
    s.dispose();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
        ],
        child: const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: PatientProfileScreen(
              patientName: 'سالم المريض',
              clinic: 'ع1',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return ProviderScope.containerOf(
      tester.element(find.byType(PatientProfileScreen)),
      listen: false,
    );
  }

  group('م171 — بطاقة المريض', () {
    testWidgets('تبويب «المواعيد» بعد الديون وقبل الأشعة وبعدّاده',
        (tester) async {
      await bootPhoneProfile(tester);
      // التبويب حاضر بعدّاد (1) — بين الديون والأشعة.
      expect(find.byKey(const Key('psec-appts')), findsOneWidget);
      expect(find.textContaining('المواعيد (1)'), findsOneWidget);
      final debtsX =
          tester.getCenter(find.byKey(const Key('psec-debts'))).dx;
      final apptsX =
          tester.getCenter(find.byKey(const Key('psec-appts'))).dx;
      final xraysX =
          tester.getCenter(find.byKey(const Key('psec-xrays'))).dx;
      // RTL: الديون يمين المواعيد، والمواعيد يمين الأشعة.
      expect(debtsX, greaterThan(apptsX));
      expect(apptsX, greaterThan(xraysX));
      expect(tester.takeException(), isNull);
    });

    testWidgets('فتح التبويب يعرض الموعد والنقر يبذر يوم الهبوط',
        (tester) async {
      final c = await bootPhoneProfile(tester);
      await tester.tap(find.byKey(const Key('psec-appts')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('pp-appt-fut1')), findsOneWidget);
      expect(find.byKey(const Key('pp-appt-book')), findsOneWidget);
      final target = ymd(day0().add(const Duration(days: 5)));
      expect(find.textContaining(target.replaceAll('-', '/')),
          findsOneWidget);
      await tester.tap(find.byKey(const Key('pp-appt-fut1')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(c.read(apptGoDayProvider), target,
          reason: 'النقر يبذر يوم الحجز للهبوط عليه');
      expect(tester.takeException(), isNull);
    });

    testWidgets('«حجز موعد» من التبويب يبذر مسودة الحجز باسم المريض',
        (tester) async {
      final c = await bootPhoneProfile(tester);
      await tester.tap(find.byKey(const Key('psec-appts')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('pp-appt-book')));
      await tester.pump(const Duration(milliseconds: 300));
      final draft = c.read(apptBookDraftProvider);
      expect(draft, isNotNull);
      expect(draft!['name'], 'سالم المريض');
      expect(draft['clinic'], 'ع1');
      expect(tester.takeException(), isNull);
    });
  });

  group('م171 — الكمبيوتر: المسودة ويوم الهبوط', () {
    Future<void> bootDesk(WidgetTester tester,
        {void Function(ProviderContainer c)? beforeCalendar}) async {
      debugForceDesktopUi = true;
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final s = ProviderContainer(overrides: [
        staffAdminSession(),
        dbDirProvider.overrideWithValue(tmp.path),
      ]);
      final auth = s.read(authServiceProvider);
      await auth.register('doc@clinic.ly', 'secret12');
      await auth.login('doc@clinic.ly', 'secret12', remember: true);
      s.read(reposProvider).settings.set('app.config', {
        'centerName': 'مركز الاختبار',
        'clinics': ['ع1', 'ع2', 'ع3'],
        'services': ['حشو'],
        'payments': ['كاش', 'تحويل'],
        'workdayStart': '09:00',
        'workdayEnd': '21:00',
      });
      s.dispose();
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
      final ok = find.byKey(const Key('appt-notif-ok'));
      if (ok.evaluate().isNotEmpty) {
        await tester.tap(ok);
        await tester.pump(const Duration(milliseconds: 200));
      }
      final c = ProviderScope.containerOf(
        tester.element(find.byType(DentalApp)),
        listen: false,
      );
      beforeCalendar?.call(c);
      await tester.tap(find.byKey(const Key('desk-tab-calendar')));
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('مسودة الحجز تفتح «موعد جديد» معبأً ومقفلاً على عيادتها',
        (tester) async {
      await bootDesk(tester, beforeCalendar: (c) {
        c.read(apptBookDraftProvider.notifier).state = {
          'name': 'سالم المريض',
          'phone': '0912345678',
          'clinic': 'ع2',
        };
      });
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('موعد جديد'), findsOneWidget);
      // الاسم والهاتف معبآن والعيادة مقفلة على ع2 (قاعدة م169).
      expect(
          tester
              .widget<TextField>(
                  find.byKey(const Key('appt-form-name')))
              .controller!
              .text,
          'سالم المريض');
      expect(find.text('العيادة: ع2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('يوم الهبوط يبدأ الجدول الأسبوعي منه', (tester) async {
      final target = ymd(day0().add(const Duration(days: 10)));
      await bootDesk(tester, beforeCalendar: (c) {
        c.read(apptGoDayProvider.notifier).state = target;
      });
      // إتاحة إطاراتٍ كافية: parent postFrame (فرض عرض الأسبوع) ثم بناء
      // WeeklyScheduler الذي يستهلك يوم الهبوط في initState.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      // عمود يوم الهبوط أول الأعمدة، واليوم الحالي خارج النافذة.
      expect(find.byKey(Key('appt-week-empty-$target')), findsOneWidget);
      expect(find.byKey(Key('appt-week-empty-${ymd(day0())}')),
          findsNothing);
      expect(c(tester).read(apptGoDayProvider), '',
          reason: 'يُستهلك مرةً ثم يُصفَّر');
      expect(tester.takeException(), isNull);
    });
  });
}

/// قارئ الحاوية من شجرة الاختبار (اختصار).
ProviderContainer Function(WidgetTester) get c => (tester) =>
    ProviderScope.containerOf(
      tester.element(find.byType(DentalApp)),
      listen: false,
    );
