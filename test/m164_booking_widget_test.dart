/// م164 — واجهة الحجوزات الجديدة: العيادة الإلزامية في الحفظ، الاستراحة
/// تمنع الحجز فوقها، دورة الحياة (إنهاء ⇒ أرشيف اليوم بلا ازدواج ثم تنظيف
/// بعد يومين بشواهد قبور)، والمُوزِّع: المتابعة تذهب لنظام الدور حين يكون
/// هو المضبوط في الإعدادات.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/core/utils/js_compat.dart'
    show getCurrentDate;
import 'package:dental_clinic_flutter/features/appointments/appointments_tab.dart';
import 'package:dental_clinic_flutter/features/queue/queue_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'staff_test_session.dart' show staffAdminSession;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('m164_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Map<String, Object?> config({List<String>? clinics, String? booking}) => {
        'centerName': 'مركز الاختبار',
        'clinics': clinics ?? ['الصفوة', 'كاريزما'],
        'services': ['حشو'],
        'payments': ['كاش'],
        'workdayStart': '09:00',
        'workdayEnd': '12:00',
        'bookingSystem': ?booking,
      };

  List<Override> ov() => [
        staffAdminSession(),
        dbDirProvider.overrideWithValue(tmp.path),
      ];

  Future<ProviderContainer> boot(
    WidgetTester t, {
    List<String>? clinics,
    String? booking,
    void Function(ProviderContainer c)? seed,
  }) async {
    t.view.physicalSize = const Size(420, 950);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final c0 = ProviderContainer(overrides: ov());
    final auth = c0.read(authServiceProvider);
    await auth.register('doc@clinic.ly', 'secret12');
    await auth.login('doc@clinic.ly', 'secret12', remember: true);
    c0
        .read(reposProvider)
        .settings
        .set('app.config', config(clinics: clinics, booking: booking));
    seed?.call(c0);
    c0.dispose();
    return ProviderContainer(overrides: ov());
  }

  Future<void> pumpTab(WidgetTester t, ProviderContainer c,
      {Widget? home}) async {
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: home ?? const AppointmentsTab()),
        ),
      ),
    ));
    await t.pump(const Duration(milliseconds: 350));
  }

  testWidgets('عيادتان: لا حفظ بلا عيادة ثم الحفظ بعيادة يكتبها مع مفتاحها',
      (t) async {
    final c = await boot(t);
    addTearDown(c.dispose);
    await pumpTab(t, c);

    // مُطالبة اختيار العيادة ظاهرة قبل التحديد.
    expect(find.text('اختر العيادة لعرض جدولها'), findsOneWidget);

    // افتح المعالج واملأ الاسم بلا عيادة ⇒ الحفظ يُمنع برسالة.
    await t.tap(find.byKey(const Key('appt-add-toggle')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('appt-name')), 'سعاد');
    await t.ensureVisible(find.byKey(const Key('appt-save')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('appt-save')), warnIfMissed: false);
    await t.pumpAndSettle();
    expect(find.textContaining('لا حجز بدون عيادة'), findsOneWidget);
    expect(c.read(reposProvider).appointments.getAll(), isEmpty,
        reason: 'مُنع الحفظ بلا عيادة');

    // اختر عيادة داخل المعالج ثم احفظ ⇒ الصف يحمل العيادة ومفتاحها.
    await t.tap(find.byKey(const Key('appt-w-clinic-كاريزما')));
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const Key('appt-save')));
    await t.tap(find.byKey(const Key('appt-save')), warnIfMissed: false);
    await t.pumpAndSettle();
    final saved = c.read(reposProvider).appointments.getAll().single;
    expect(saved['clinic'], 'كاريزما');
    expect('${saved['clinic_id']}'.isNotEmpty, isTrue);
    expect(saved['status'], 'pending');
  });

  testWidgets('الاستراحة ☕ تمنع الحجز فوقها منعاً قاطعاً', (t) async {
    final today = getCurrentDate();
    final c = await boot(t, clinics: ['ع1'], seed: (c0) {
      c0.read(reposProvider).appointments.upsertLocal({
        'id': 'brk1',
        'name': 'غداء',
        'date': today,
        'time': '10:00',
        'durationMin': 60,
        'isBreak': 1,
        'status': 'pending',
        'clinic': 'ع1',
        '_t': 'a',
      });
    });
    addTearDown(c.dispose);
    await pumpTab(t, c);

    // الاستراحة ظاهرة في الـ Timeline بأسلوبها.
    expect(find.textContaining('غداء'), findsWidgets);

    // خانة داخل مدى الاستراحة (10:30) معطلة موسومة ☕ — نقرها لا يختار.
    await t.tap(find.byKey(const Key('appt-add-toggle')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('appt-name')), 'مريض');
    await t.ensureVisible(find.byKey(const Key('appt-slot-09:30')));
    // 09:30 حرة (30د تنتهي عند حد الاستراحة تماماً) — تُختار وتُحفظ.
    await t.tap(find.byKey(const Key('appt-slot-09:30')),
        warnIfMissed: false);
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const Key('appt-save')));
    await t.tap(find.byKey(const Key('appt-save')), warnIfMissed: false);
    await t.pumpAndSettle();
    final ok = c
        .read(reposProvider)
        .appointments
        .getAll()
        .where((a) => a['name'] == 'مريض')
        .toList();
    expect(ok, hasLength(1));
    expect(ok.single['time'], '09:30');
    // تصريف سنackbar الحفظ (تصطف الرسائل في ScaffoldMessenger).
    await t.pump(const Duration(seconds: 5));
    await t.pumpAndSettle();

    // منع قاطع: اختر 11:00 الحرة ثم ارفع المدة 90 (تخترق... لا: 11:00
    // بعد الاستراحة). نختار 09:30 مجدداً (مشغولة بموعد ⇒ تحذير قابل
    // للتجاوز) لكن بمدة 60 تخترق الاستراحة ⇒ يُمنع قبل أي تحذير.
    await t.tap(find.byKey(const Key('appt-add-toggle')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('appt-name')), 'متعارض');
    await t.ensureVisible(find.byKey(const Key('appt-slot-09:30')));
    await t.tap(find.byKey(const Key('appt-slot-09:30')),
        warnIfMissed: false);
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('appt-duration')), '60');
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const Key('appt-save')));
    await t.tap(find.byKey(const Key('appt-save')), warnIfMissed: false);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('appt-conflict-save')), findsNothing,
        reason: 'الاستراحة تُفحص قبل تحذير الموعد — لا حوار تجاوز');
    expect(find.textContaining('لا يمكن الحجز فوق استراحة'), findsOneWidget);
    expect(
        c
            .read(reposProvider)
            .appointments
            .getAll()
            .where((a) => a['name'] == 'متعارض'),
        isEmpty,
        reason: 'التداخل مع الاستراحة منعٌ قاطع لا يتجاوزه تأكيد');
  });

  testWidgets(
      'دورة الحياة: إنهاء ⇒ أرشيف اليوم بلا ازدواج، والتنظيف بعد يومين',
      (t) async {
    final today = getCurrentDate();
    final c = await boot(t, clinics: ['ع1'], seed: (c0) {
      final repos = c0.read(reposProvider);
      repos.appointments.upsertLocal({
        'id': 'a1',
        'name': 'وليد',
        'date': today,
        'time': '09:00',
        'service': 'كشف',
        'status': 'pending',
        'clinic': 'ع1',
        '_t': 'a',
      });
      // مؤرشف قديم (3 أيام) — يجب أن يُنظَّف عند فتح الشاشة.
      repos.appointments.upsertLocal({
        'id': 'old1',
        'name': 'قديم',
        'date': '2020-01-01',
        'status': 'completed',
        'archivedOn': '2020-01-01',
        'clinic': 'ع1',
        '_t': 'a',
      });
    });
    addTearDown(c.dispose);
    await pumpTab(t, c);
    await t.pumpAndSettle();

    // التنظيف: المؤرشف الأقدم من يومين حُذف (شاهد قبر).
    expect(c.read(reposProvider).appointments.getById('old1'), isNull,
        reason: 'أرشيف يتجاوز يومين يُحذف عند الفتح');

    // إنهاء الزيارة من زر ✓ على البطاقة.
    await t.ensureVisible(find.byKey(const Key('appt-done-a1')));
    await t.tap(find.byKey(const Key('appt-done-a1')), warnIfMissed: false);
    await t.pumpAndSettle();

    final row = c.read(reposProvider).appointments.getById('a1')!;
    expect(row['status'], 'completed');
    expect(row['archivedOn'], today, reason: 'ختم يوم الأرشفة');

    // البطاقة انتقلت للأرشيف: لا صف نشط، وقسم الأرشيف يعدّ 1 — لا ازدواج.
    expect(find.byKey(const Key('appt-done-a1')), findsNothing);
    expect(find.textContaining('أرشيف اليوم (1)'), findsOneWidget);
    expect(find.textContaining('0 موعد'), findsOneWidget,
        reason: 'المؤرشف لا يُحسب في عدّاد الجدول الحالي');

    // التراجع يعيده للجدول.
    await t.ensureVisible(find.byKey(const Key('appt-undone-a1')));
    await t.tap(find.byKey(const Key('appt-undone-a1')),
        warnIfMissed: false);
    await t.pumpAndSettle();
    expect(c.read(reposProvider).appointments.getById('a1')!['status'],
        'upcoming');
    expect(find.textContaining('1 موعد'), findsOneWidget);
  });

  testWidgets('م165 — خمس عيادات: زر منسدل بورقة اختيار بدل رقائق ملتفة',
      (t) async {
    final today = getCurrentDate();
    final five = ['الصفوة', 'كاريزما', 'د.عبدالكريم', 'د.ملاذ', 'الدليمي'];
    final c = await boot(t, clinics: five, seed: (c0) {
      c0.read(reposProvider).appointments.upsertLocal({
        'id': 'x1',
        'name': 'مريض',
        'date': today,
        'time': '09:00',
        'status': 'pending',
        'clinic': 'كاريزما',
        '_t': 'a',
      });
    });
    addTearDown(c.dispose);
    await pumpTab(t, c);

    // ≥4 عيادات ⇒ لا رقائق سطرية، بل زر منسدل واحد.
    expect(find.byKey(const Key('appt-clinic-pill')), findsOneWidget);
    expect(find.byKey(const Key('appt-clinic-الصفوة')), findsNothing,
        reason: 'لا رقائق في الرأس عند ≥4 عيادات');

    // فتح الورقة واختيار كاريزما (بعدّاد مواعيد اليوم).
    await t.tap(find.byKey(const Key('appt-clinic-pill')));
    await t.pumpAndSettle();
    expect(find.text('اختر العيادة'), findsWidgets);
    expect(find.textContaining('1 اليوم'), findsOneWidget,
        reason: 'عدّاد مواعيد اليوم بجانب كاريزما');
    await t.tap(find.byKey(const Key('appt-clinic-كاريزما')));
    await t.pumpAndSettle();

    // الجدول يعرض موعد كاريزما مباشرة.
    expect(find.byKey(const Key('appt-row-x1')), findsOneWidget);
    expect(find.textContaining('1 موعد'), findsOneWidget);
  });

  testWidgets('المُوزِّع: نوع الحجز «بالدور» يستقبل المتابعة بعيادة سجلها',
      (t) async {
    final c = await boot(t, booking: 'queue');
    // لوحة الدور مصممة لعرضٍ أوسع — الاختبار سلوكي لا تخطيطي.
    t.view.physicalSize = const Size(900, 950);
    addTearDown(c.dispose);
    // مسودة متابعة قادمة من «زيارة جديدة» بعيادة السجل.
    c.read(followUpDraftProvider.notifier).state = {
      'name': 'هدى',
      'phone': '0917777777',
      'service': 'حشو',
      'clinic': 'كاريزما',
    };
    await pumpTab(t, c, home: const QueueScreen());
    await t.pumpAndSettle();

    // فُتحت لوحة عيادة السجل مباشرة (لا شاشة الاختيار) بنموذج مسبق التعبئة.
    expect(find.textContaining('كاريزما'), findsWidgets);
    final nameField = t.widget<TextField>(find.byKey(const Key('queue-add-name')));
    expect(nameField.controller!.text, 'هدى');
  });
}
