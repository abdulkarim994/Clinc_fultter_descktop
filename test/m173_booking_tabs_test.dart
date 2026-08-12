/// م173 — واجهة الحجز الجديدة: رأس «الحجز» بمحدد عيادةٍ كبير، ثلاثة
/// تبويبات بمؤشر منزلق (الجدول/أرشيف اليوم/القادمة)، الأرشيف بفلاتر
/// حالته في تبويبه، القادمة مجمعةً بالأيام والنقر يقفز ليوم الحجز في
/// الجدول، وفهرس التبويب يبقى خلال الجلسة (مزوّد).
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/core/utils/js_compat.dart'
    show getCurrentDate;
import 'package:dental_clinic_flutter/features/appointments/appointments_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'staff_test_session.dart' show staffAdminSession;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('m173t_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  String ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  List<Override> ov() => [
        staffAdminSession(),
        dbDirProvider.overrideWithValue(tmp.path),
      ];

  Future<ProviderContainer> boot(
    WidgetTester t, {
    List<String>? clinics,
    void Function(ProviderContainer c)? seed,
  }) async {
    t.view.physicalSize = const Size(420, 1000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final c0 = ProviderContainer(overrides: ov());
    final auth = c0.read(authServiceProvider);
    await auth.register('doc@clinic.ly', 'secret12');
    await auth.login('doc@clinic.ly', 'secret12', remember: true);
    c0.read(reposProvider).settings.set('app.config', {
      'centerName': 'مركز الاختبار',
      'clinics': clinics ?? ['ع1'],
      'services': ['حشو'],
      'payments': ['كاش'],
      'workdayStart': '09:00',
      'workdayEnd': '12:00',
    });
    seed?.call(c0);
    c0.dispose();
    return ProviderContainer(overrides: ov());
  }

  Future<void> pumpTab(WidgetTester t, ProviderContainer c) async {
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: AppointmentsTab()),
        ),
      ),
    ));
    await t.pump(const Duration(milliseconds: 350));
  }

  Map<String, Object?> appt(String id, String date,
          {String? time,
          String status = 'pending',
          String clinic = 'ع1',
          String name = 'مريض',
          String? archivedOn}) =>
      {
        'id': id,
        'name': name,
        'date': date,
        'time': ?time,
        'status': status,
        'archivedOn': ?archivedOn,
        'clinic': clinic,
        '_t': 'a',
      };

  testWidgets('الرأس: «الحجز» يميناً ومحدد العيادة الكبير يساراً',
      (t) async {
    final c = await boot(t, clinics: ['الصفوة', 'كاريزما']);
    addTearDown(c.dispose);
    await pumpTab(t, c);

    // العنوان الكبير + المحدد الكبير (لا رقائق سطرية بعد الآن).
    expect(find.text('الحجز'), findsOneWidget);
    final pill = find.byKey(const Key('appt-clinic-pill'));
    expect(pill, findsOneWidget);
    // RTL: العنوان يمين المحدد.
    final titleX = t.getCenter(find.text('الحجز')).dx;
    final pillX = t.getCenter(pill).dx;
    expect(titleX, greaterThan(pillX));
    // التبويبات الثلاثة حاضرة والجدول الافتراضي.
    expect(find.byKey(const Key('appt-tab-schedule')), findsOneWidget);
    expect(find.byKey(const Key('appt-tab-archive')), findsOneWidget);
    expect(find.byKey(const Key('appt-tab-upcoming')), findsOneWidget);
    expect(find.byKey(const Key('appt-view-schedule')), findsOneWidget);

    // المحدد يفتح الورقة ويختار — عيادتان تعملان عبر الورقة أيضاً (م173).
    await t.tap(pill);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('appt-clinic-كاريزما')));
    await t.pumpAndSettle();
    expect(c.read(apptClinicProvider), 'كاريزما');
    expect(t.takeException(), isNull);
  });

  testWidgets('أرشيف اليوم في تبويبه بفلاتر الحالة', (t) async {
    final today = getCurrentDate();
    final c = await boot(t, seed: (c0) {
      final repos = c0.read(reposProvider);
      repos.appointments.upsertLocal(
          appt('c1', today, status: 'completed', archivedOn: today,
              name: 'منجز'));
      repos.appointments.upsertLocal(
          appt('c2', today, status: 'cancelled', archivedOn: today,
              name: 'ملغي'));
      repos.appointments.upsertLocal(
          appt('c3', today, status: 'no_show', archivedOn: today,
              name: 'غائب'));
    });
    addTearDown(c.dispose);
    await pumpTab(t, c);

    // الجدول لا يعرض الأرشيف (انفصل كلياً).
    expect(find.byKey(const Key('appt-archive-title')), findsNothing);

    await t.tap(find.byKey(const Key('appt-tab-archive')));
    await t.pumpAndSettle();
    expect(find.textContaining('أرشيف اليوم (3)'), findsOneWidget);
    expect(find.text('منجز'), findsOneWidget);
    expect(find.text('ملغي'), findsOneWidget);

    // فلتر «ملغى» يبقي صفه وحده.
    await t.tap(find.byKey(const Key('appt-arch-f-cancelled')));
    await t.pumpAndSettle();
    expect(find.text('ملغي'), findsOneWidget);
    expect(find.text('منجز'), findsNothing);
    expect(find.text('غائب'), findsNothing);

    // «الكل» يعيد الجميع.
    await t.tap(find.byKey(const Key('appt-arch-f-all')));
    await t.pumpAndSettle();
    expect(find.text('منجز'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('القادمة مجمعةً بالأيام والنقر يقفز ليوم الحجز بالجدول',
      (t) async {
    final now = DateTime.now();
    final d1 = ymd(DateTime(now.year, now.month, now.day)
        .add(const Duration(days: 3)));
    final d2 = ymd(DateTime(now.year, now.month, now.day)
        .add(const Duration(days: 5)));
    final c = await boot(t, seed: (c0) {
      final repos = c0.read(reposProvider);
      repos.appointments
          .upsertLocal(appt('u1', d1, time: '09:00', name: 'أول'));
      repos.appointments
          .upsertLocal(appt('u2', d1, time: '10:00', name: 'ثانٍ'));
      repos.appointments
          .upsertLocal(appt('u3', d2, time: '11:00', name: 'ثالث'));
    });
    addTearDown(c.dispose);
    await pumpTab(t, c);

    await t.tap(find.byKey(const Key('appt-tab-upcoming')));
    await t.pumpAndSettle();
    // رأسا اليومين حاضران (تاريخ + اسم اليوم).
    expect(find.textContaining(d1), findsOneWidget);
    expect(find.textContaining(d2), findsOneWidget);
    expect(find.byKey(const Key('upcoming-u1')), findsOneWidget);

    // النقر على موعد اليوم الثاني يفتح الجدول على يومه.
    await t.tap(find.byKey(const Key('upcoming-u3')));
    await t.pumpAndSettle();
    expect(c.read(apptViewTabProvider), 0,
        reason: 'القفزة تعيد لتبويب الجدول');
    expect(find.byKey(const Key('appt-view-schedule')), findsOneWidget);
    expect(find.textContaining('ثالث'), findsWidgets,
        reason: 'جدول اليوم المقصود يعرض موعده');
    expect(t.takeException(), isNull);
  });

  testWidgets('فهرس التبويب يبقى خلال الجلسة (المزوّد)', (t) async {
    final c = await boot(t);
    addTearDown(c.dispose);
    await pumpTab(t, c);
    expect(c.read(apptViewTabProvider), 0);
    await t.tap(find.byKey(const Key('appt-tab-upcoming')));
    await t.pumpAndSettle();
    expect(c.read(apptViewTabProvider), 2);

    // إعادة بناء الشاشة (مغادرة وعودة) تفتح التبويب المحفوظ نفسه.
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: SizedBox()),
        ),
      ),
    ));
    await pumpTab(t, c);
    expect(find.byKey(const Key('appt-view-upcoming')), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
