/// اختبارات الجدولة الأسبوعية المكتبية (Weekly Scheduler) + مقابلاتها الهاتفية:
///   • العرض الافتراضي هو الجدولة الأسبوعية (appt.view='week').
///   • بطاقة الموعد تظهر في عمود يومها ووقتها.
///   • النقل (سحب رأسي) يحدّث time مع بقاء date (النقل عبر الأجهزة يحرسه
///     m52_rows_two_device_test).
///   • النسخ من الـpopover يفتح النموذج مسبق التعبئة ثم الحفظ ينشئ صفاً
///     جديداً بمعرّفٍ مختلف (بلا حقول تكرار/تخزين منسوخة).
///   • durationMin يُحفظ من النموذج ويُقرأ (حقلٌ مرن في كتلة data).
///   • مبدّل العرض يبدّل بين الجدولة والقائمة ويُحفظ.
///   • المدة بالهاتف تُحفظ ضمن upsertLocal للموعد.
///
/// نمط الإقلاع كـ desktop_appointments_test: جلسة إدارة + dbDir + قسر واجهة
/// المكتب + مقاس كبير. حاوية شجرة الودجت تُقرأ منها كتابات الواجهة مباشرة.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/features/appointments/appointments_tab.dart'
    show apptRevProvider;
import 'package:dental_clinic_flutter/features/desktop/desktop_gate.dart';
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'staff_test_session.dart' show staffAdminSession;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('desk_week_'));
  tearDown(() {
    debugForceDesktopUi = null;
    tmp.deleteSync(recursive: true);
  });

  /// م169 — الأسبوع متدحرجٌ يبدأ من اليوم: نبذر «الغد» (ثاني عمود —
  /// مرئيٌّ دائماً وغير ماضٍ) بدل اثنين أسبوع السبت الذي قد يكون ماضياً
  /// فيقفله عقد «الأيام السابقة للعرض فقط» الجديد.
  DateTime tomorrow() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day).add(const Duration(days: 1));
  }

  String ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// يُقلع التطبيق على تبويب الحجوزات (يبقى على العرض الأسبوعي الافتراضي).
  /// [seed] يُبذر مواعيد على قاعدة الشجرة قبل الدخول للتبويب.
  Future<ProviderContainer> boot(
    WidgetTester tester, {
    void Function(ProviderContainer c)? seed,
  }) async {
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
      'clinics': ['ع1'],
      'services': ['حشو', 'قلع'],
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

    // بذر المواعيد (بعد الإقلاع كي تُقرأ من قاعدة الشجرة نفسها).
    if (seed != null) {
      final c = ProviderScope.containerOf(
        tester.element(find.byType(DentalApp)),
        listen: false,
      );
      seed(c);
      c.read(apptRevProvider.notifier).state++;
      await tester.pump(const Duration(milliseconds: 100));
    }

    // إغلاق حوار تذكير المواعيد إن ظهر.
    final ok = find.byKey(const Key('appt-notif-ok'));
    if (ok.evaluate().isNotEmpty) {
      await tester.tap(ok);
      await tester.pump(const Duration(milliseconds: 200));
    }

    await tester.tap(find.byKey(const Key('desk-tab-calendar')));
    await tester.pump(const Duration(milliseconds: 300));

    return ProviderScope.containerOf(
      tester.element(find.byType(DentalApp)),
      listen: false,
    );
  }

  testWidgets('العرض الافتراضي هو الجدولة الأسبوعية', (tester) async {
    await boot(tester);
    // الجدولة الأسبوعية حاضرة، وعرض القائمة غائب.
    expect(find.byKey(const Key('appt-week-view')), findsOneWidget);
    expect(find.byKey(const Key('appt-week-scroll')), findsOneWidget);
    expect(find.byKey(const Key('appt-desk-list')), findsNothing);
    // رأس الأسبوع وأزرار التنقل موجودة.
    expect(find.byKey(const Key('appt-week-range')), findsOneWidget);
    expect(find.byKey(const Key('appt-week-today')), findsOneWidget);
  });

  testWidgets('بطاقة الموعد تظهر في يومها ووقتها', (tester) async {
    // موعدٌ يوم الاثنين من الأسبوع الحالي الساعة 10:00.
    final date = ymd(tomorrow()); // م169 — الغد: مرئيٌّ وغير ماضٍ.
    final container = await boot(tester, seed: (c) {
      c.read(reposProvider).appointments.upsertLocal({
        'id': 'w1',
        'name': 'سالم الأسبوعي',
        'phone': '0911000000',
        'date': date,
        'time': '10:00',
        'service': 'كشف',
        'status': 'pending',
        'clinic_id': '',
        '_t': 'a',
      });
    });

    // البطاقة ظاهرة.
    expect(find.byKey(const Key('appt-week-card-w1')), findsOneWidget);
    expect(find.text('سالم الأسبوعي'), findsOneWidget);
    // الصف موجود بالقاعدة بوقته الأصلي.
    final row = container.read(reposProvider).appointments.getById('w1')!;
    expect(row['time'], '10:00');
    expect(row['date'], date);
  });

  testWidgets('النقل بالسحب الرأسي يحدّث الوقت ويُبقي التاريخ', (tester) async {
    final date = ymd(tomorrow()); // م169 — الغد: مرئيٌّ وغير ماضٍ.
    final container = await boot(tester, seed: (c) {
      c.read(reposProvider).appointments.upsertLocal({
        'id': 'w2',
        'name': 'نقل الموعد',
        'date': date,
        'time': '10:00',
        'service': 'كشف',
        'status': 'pending',
        'clinic_id': '',
        '_t': 'a',
      });
    });

    final card = find.byKey(const Key('appt-week-card-w2'));
    expect(card, findsOneWidget);

    // سحبٌ رأسي للأسفل بمقدارٍ كبير (ارتفاع الساعة 64px، تقطيع 15د). نتحقق
    // من سلوك النقل: التاريخ ثابت، والوقت تقدّم إلى خانةٍ مقطّعةٍ على 15
    // دقيقة (المقدار الدقيق يتأثر بعتبة السحب فلا نثبّته). ندفع مسافةً تتجاوز
    // العتبة بوضوحٍ (~ساعتين).
    await tester.drag(card, const Offset(0, 128));
    await tester.pump(const Duration(milliseconds: 300));

    final row = container.read(reposProvider).appointments.getById('w2')!;
    expect(row['date'], date, reason: 'التاريخ ثابت (سحب رأسي داخل اليوم)');
    final t = '${row['time']}';
    expect(t, isNot('10:00'), reason: 'الوقت تغيّر بالسحب');
    // الوقت الجديد بعد 10:00 (سحبٌ للأسفل) ومقطّعٌ على 15 دقيقة.
    expect(t.compareTo('10:00') > 0, isTrue,
        reason: 'السحب للأسفل يقدّم الوقت');
    final mm = int.parse(t.split(':')[1]);
    expect(mm % 15, 0, reason: 'الوقت مقطّعٌ على 15 دقيقة (snap)');
    // لا صفٌّ جديد — نقلٌ لا نسخ.
    expect(container.read(reposProvider).appointments.getAll().length, 1);
  });

  testWidgets('النسخ من الـpopover ينشئ صفاً جديداً بمعرّفٍ مختلف',
      (tester) async {
    final date = ymd(tomorrow()); // م169 — الغد: مرئيٌّ وغير ماضٍ.
    final container = await boot(tester, seed: (c) {
      c.read(reposProvider).appointments.upsertLocal({
        'id': 'w3',
        'name': 'نسخة الموعد',
        'phone': '0912000000',
        'date': date,
        'time': '12:00',
        'service': 'تنظيف',
        'notes': 'ملاحظة',
        'durationMin': 45,
        'status': 'pending',
        'clinic_id': '',
        '_t': 'a',
      });
    });

    // افتح الـpopover ثم «نسخ».
    await tester.tap(find.byKey(const Key('appt-week-card-w3')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('appt-week-details-w3')), findsOneWidget);
    await tester.tap(find.byKey(const Key('appt-week-copy-w3')));
    await tester.pump(const Duration(milliseconds: 300));

    // نموذج الإضافة مفتوحٌ مسبق التعبئة — احفظ.
    expect(find.byKey(const Key('appt-form-name')), findsOneWidget);
    // الاسم والمدة معبّآن.
    final nameField =
        tester.widget<TextField>(find.byKey(const Key('appt-form-name')));
    expect(nameField.controller!.text, 'نسخة الموعد');
    final durField =
        tester.widget<TextField>(find.byKey(const Key('appt-form-duration')));
    expect(durField.controller!.text, '45');

    await tester.tap(find.byKey(const Key('appt-form-save')));
    await tester.pump(const Duration(milliseconds: 300));

    // صفّان الآن: الأصل + النسخة بمعرّفٍ مختلف، والنسخة موعدٌ مفرد pending.
    final all = container.read(reposProvider).appointments.getAll();
    expect(all.length, 2, reason: 'النسخ ينشئ صفاً جديداً');
    final copy = all.firstWhere((r) => '${r['id']}' != 'w3');
    expect('${copy['id']}'.isNotEmpty, isTrue);
    expect(copy['id'], isNot('w3'), reason: 'معرّفٌ جديد');
    expect(copy['name'], 'نسخة الموعد');
    expect(copy['service'], 'تنظيف');
    expect((copy['durationMin'] as num).toInt(), 45);
    expect(copy['status'], 'pending');
    // بلا حقول تكرار.
    expect(copy['repeatGroup'], isNull);
  });

  testWidgets('durationMin يُحفظ من النموذج ويُقرأ', (tester) async {
    final container = await boot(tester);

    // نقر خانةٍ فارغة في عمود اليوم يفتح النموذج بتاريخ/وقتٍ مسبقين.
    // نفتح النموذج مباشرةً عبر مبدّل القائمة ثم زر الإضافة (أضمن من إحداثيات
    // الخانة الفارغة). بدّل للقائمة، أضف موعداً بمدة.
    await tester.tap(find.text('قائمة'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('appt-desk-add')));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(
        find.byKey(const Key('appt-form-name')), 'صاحب المدة');
    await tester.pump();
    await tester.enterText(
        find.byKey(const Key('appt-form-duration')), '90');
    await tester.pump();
    await tester.tap(find.byKey(const Key('appt-form-save')));
    await tester.pump(const Duration(milliseconds: 300));

    final row = container.read(reposProvider).appointments.getAll().single;
    expect(row['name'], 'صاحب المدة');
    expect((row['durationMin'] as num).toInt(), 90,
        reason: 'المدة محفوظة في كتلة data وتُقرأ');
  });

  testWidgets('مبدّل العرض يبدّل بين الجدولة والقائمة ويُحفظ', (tester) async {
    await boot(tester);
    // الافتراضي: الجدولة.
    expect(find.byKey(const Key('appt-week-view')), findsOneWidget);

    // بدّل إلى القائمة.
    await tester.tap(find.text('قائمة'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('appt-week-view')), findsNothing);
    expect(find.byKey(const Key('appt-desk-add')), findsOneWidget);

    // ارجع إلى الجدولة.
    await tester.tap(find.text('أسبوع'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('appt-week-view')), findsOneWidget);
    expect(find.byKey(const Key('appt-desk-add')), findsNothing);
  });

  testWidgets('durationMin من نموذج تعديل يُحدّث الصف عبر الجدولة',
      (tester) async {
    final date = ymd(tomorrow()); // م169 — الغد: مرئيٌّ وغير ماضٍ.
    final container = await boot(tester, seed: (c) {
      c.read(reposProvider).appointments.upsertLocal({
        'id': 'w4',
        'name': 'تعديل المدة',
        'date': date,
        'time': '13:00',
        'service': 'حشو',
        'status': 'pending',
        'clinic_id': '',
        '_t': 'a',
      });
    });

    // popover ⇒ تعديل ⇒ اضبط المدة 60 ⇒ حفظ.
    await tester.tap(find.byKey(const Key('appt-week-card-w4')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('appt-week-edit-w4')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(
        find.byKey(const Key('appt-form-duration')), '60');
    await tester.pump();
    await tester.tap(find.byKey(const Key('appt-form-save')));
    await tester.pump(const Duration(milliseconds: 300));

    final row = container.read(reposProvider).appointments.getById('w4')!;
    expect((row['durationMin'] as num).toInt(), 60);
    // النقل الثلاثي لم يمس بقية الحقول.
    expect(row['time'], '13:00');
    expect(row['name'], 'تعديل المدة');
  });
}
