/// اختبارات م8 — نظام الحجز الثنائي (تقويم المواعيد التقليدي + بوابة التبديل):
///   • وحدات: دمج مصادر apptMap الثلاثة، شبكة الشهر الأحدية، dayLabel،
///     to12h، القادمة (تصفية الحالة والتاريخ وحد 12)، دين المريض،
///     نصوص التذكير، fuzzyMatch/اقتراحات الأسماء وتعبئة الهاتف.
///   • واجهة: الافتراضي تقليدي والتبديل الحي من الإعدادات في الاتجاهين،
///     إضافة موعد يظهر في الشبكة واليوم والقاعدة، إتمام/تراجع، حذف بعداد
///     المواعيد، موعد متابعة من شاشة الإضافة يعود للرئيسية (followUpAuto)،
///     إشعار مواعيد اليوم/الغد عند الفتح.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/core/utils/js_compat.dart';
import 'package:dental_clinic_flutter/features/appointments/appointments_logic.dart';
import 'package:dental_clinic_flutter/features/shell/app_shell.dart'
    show resetApptNotifGuard;
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'staff_test_session.dart' show staffAdminSession;

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('m8_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Map<String, Object?> config() => {
    'centerName': 'مركز الاختبار',
    'clinics': ['ع1'],
    'services': ['حشو', 'تركيبات'],
    'payments': ['كاش'],
  };

  ProviderContainer container() => ProviderContainer(
    overrides: [staffAdminSession(), dbDirProvider.overrideWithValue(tmp.path)],
  );

  group('الوحدات — منطق التقويم', () {
    test('apptMap يدمج المواعيد وحقل appointment في السجلات والتركيبات', () {
      final map = buildApptMap(
        appointments: [
          {'id': 'a1', 'name': 'أ', 'date': '2026-07-10'},
        ],
        records: [
          {
            'id': 'r1',
            'name': 'ب',
            'appointment': '2026-07-10',
            'service': 'حشو',
          },
          {'id': 'r2', 'name': 'ج'}, // بلا موعد — لا يظهر
        ],
        prosthetics: [
          {'id': 'p1', 'name': 'د', 'appointment': '2026-07-11'},
        ],
      );
      expect(map['2026-07-10'], hasLength(2));
      expect(map['2026-07-11'], hasLength(1));
      final rec = map['2026-07-10']!.firstWhere((a) => a['_src'] == 'rec');
      expect(rec['id'], 'rec-r1');
      expect(rec['status'], 'upcoming');
      final pros = map['2026-07-11']!.single;
      expect(pros['service'], 'تركيبات');
      expect(pros['id'], 'pros-p1');
    });

    test('شبكة الشهر أحدية البداية وخلايا الجوار معطلة والعدادات صحيحة', () {
      // يوليو 2026: يبدأ أربعاء (غرة 2026-07-01 = الأربعاء ⇒ 3 خلايا سابقة).
      final cells = calendarCells(2026, 6, {
        '2026-07-10': [
          {'name': 'أ'},
          {'name': 'ب'},
          {'name': 'ج'},
        ],
      });
      expect(cells.length % 7, 0);
      expect(cells.take(3).every((c) => c.other), isTrue);
      final d10 = cells.firstWhere((c) => c.dateStr == '2026-07-10');
      expect(d10.apptCount, 3);
      expect(d10.names, 'أ، ب...');
      // 3 سابقة + 31 يوماً = 34 ⇒ إكمال إلى 35.
      expect(cells.length, 35);
    });

    test('dayLabel وto12h حرفيان', () {
      final today = getCurrentDate();
      expect(dayLabel(today), 'اليوم');
      final t = DateTime.now().add(const Duration(days: 1));
      final tmrw =
          '${t.year.toString().padLeft(4, '0')}-'
          '${t.month.toString().padLeft(2, '0')}-'
          '${t.day.toString().padLeft(2, '0')}';
      expect(dayLabel(tmrw), 'غداً');
      expect(to12h('14:30'), '2:30 م');
      expect(to12h('09:05'), '9:05 ص');
      expect(to12h('00:15'), '12:15 ص');
      expect(to12h(''), '');
    });

    test('القادمة: من اليوم فصاعداً بلا مكتمل/ملغي وبحد 12', () {
      final today = getCurrentDate();
      final map = buildApptMap(
        appointments: [
          {'id': 'a0', 'name': 'ماضٍ', 'date': '2020-01-01'},
          {'id': 'a1', 'name': 'اليوم', 'date': today},
          {'id': 'a2', 'name': 'مكتمل', 'date': today, 'status': 'completed'},
          {'id': 'a3', 'name': 'ملغي', 'date': today, 'status': 'cancelled'},
          for (var i = 0; i < 15; i++)
            {'id': 'f$i', 'name': 'قادم$i', 'date': '2099-01-01'},
        ],
        records: const [],
        prosthetics: const [],
      );
      final up = upcomingAppts(map);
      expect(up, hasLength(12));
      expect(up.first['name'], 'اليوم');
      expect(up.any((a) => a['name'] == 'مكتمل'), isFalse);
      expect(up.any((a) => a['name'] == 'ملغي'), isFalse);
      expect(up.any((a) => a['name'] == 'ماضٍ'), isFalse);
    });

    test('دين المريض ونصوص التذكير الحرفية', () {
      final debts = [
        {'id': 'd1', 'name': 'أحمد', 'remaining': 150, 'status': 'partial'},
        {'id': 'd2', 'name': 'أحمد', 'remaining': 50, 'status': 'paid'},
        {'id': 'd3', 'name': 'غيره', 'remaining': 70, 'status': 'partial'},
      ];
      expect(getPatientDebt(debts, 'أحمد'), 150);
      expect(getPatientDebt(debts, ''), 0);

      final a = {
        'name': 'أحمد',
        'date': '2026-07-27',
        'time': '14:30',
        'service': 'كشف',
      };
      final wa = waReminderText(a, 'مركزنا');
      expect(wa.contains('*مركزنا*'), isTrue);
      expect(wa.contains('تذكير بموعدكم'), isTrue);
      expect(wa.contains('*أحمد*'), isTrue);
      expect(wa.contains('2:30 م'), isTrue);
      expect(wa.contains('🦷 الخدمة: كشف'), isTrue);
      final sms = smsReminderText(a, 'مركزنا');
      expect(sms.contains('نرجو التأكيد'), isTrue);
      final dwa = debtWaText(a, 150, 'د.ل', 'مركزنا');
      expect(dwa.contains('150 د.ل'), isTrue);
      expect(dwa.contains('تذكير بالمبلغ المتبقي'), isTrue);
    });

    test('fuzzyMatch والاقتراحات وتعبئة الهاتف من الأحدث', () {
      expect(fuzzyMatch('احمد', 'أحمد علي'), isTrue); // تطبيع الهمزة
      expect(fuzzyMatch('xy', 'أحمد'), isFalse);
      final recs = [
        {
          'id': 'r1',
          'name': 'أحمد علي',
          'date': '2026-01-01',
          'phone': '0911111111',
        },
        {
          'id': 'r2',
          'name': 'أحمد علي',
          'date': '2026-06-01',
          'phone': '0922222222',
        },
        {'id': 'r3', 'name': 'سالم', 'date': '2026-05-01'},
      ];
      final sugg = apptNameSuggestions('احمد', recs, const []);
      expect(sugg, ['أحمد علي']);
      // الأحدث تاريخاً يفوز بهاتفه.
      expect(
        phoneForName(
          'أحمد علي',
          records: recs,
          prosthetics: const [],
          debts: const [],
          appointments: const [],
        ),
        '0922222222',
      );
    });
  });

  group('الواجهة — البوابة والتقويم', () {
    Future<void> boot(
      WidgetTester tester, {
      void Function(ProviderContainer c)? seed,
      Map<String, Object?>? cfgOverride,
    }) async {
      final c = container();
      final auth = c.read(authServiceProvider);
      await auth.register('doc@clinic.ly', 'secret12');
      await auth.login('doc@clinic.ly', 'secret12', remember: true);
      c.read(reposProvider).settings.set('app.config', cfgOverride ?? config());
      seed?.call(c);
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
      await tester.pump(const Duration(milliseconds: 120));
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('الافتراضي تقليدي والتبديل من الإعدادات حيّ بالاتجاهين', (
      tester,
    ) async {
      await boot(tester);
      await tester.tap(find.text('الحجوزات'), warnIfMissed: false);
      await settle(tester);
      // الافتراضي: التقويم التقليدي.
      expect(find.byKey(const Key('appointments-tab')), findsOneWidget);
      expect(find.text('جدول المواعيد'), findsOneWidget);

      // بدّل إلى نظام الدور من الإعدادات.
      await tester.tap(find.byTooltip('الإعدادات'));
      await settle(tester);
      await tester.tap(
        find.byKey(const Key('group-booking')),
        warnIfMissed: false,
      );
      await settle(tester);
      await tester.ensureVisible(find.text('نظام الدور'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('نظام الدور'), warnIfMissed: false);
      await settle(tester);
      // م92 — رجوعان: صفحة القسم ثم شاشة الإعدادات.
      await tester.tap(
        find.byKey(const Key('settings-section-back')),
        warnIfMissed: false,
      );
      await settle(tester);
      await tester.tap(find.byType(BackButton).first, warnIfMissed: false);
      await settle(tester);
      expect(find.byKey(const Key('appointments-tab')), findsNothing);
      expect(find.text('الحجوزات — نظام الدور'), findsOneWidget);

      // والعودة إلى التقليدي.
      await tester.tap(find.byTooltip('الإعدادات'));
      await settle(tester);
      await tester.tap(
        find.byKey(const Key('group-booking')),
        warnIfMissed: false,
      );
      await settle(tester);
      await tester.ensureVisible(find.text('النظام التقليدي'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('النظام التقليدي'), warnIfMissed: false);
      await settle(tester);
      // م92 — رجوعان: صفحة القسم ثم شاشة الإعدادات.
      await tester.tap(
        find.byKey(const Key('settings-section-back')),
        warnIfMissed: false,
      );
      await settle(tester);
      await tester.tap(find.byType(BackButton).first, warnIfMissed: false);
      await settle(tester);
      expect(find.byKey(const Key('appointments-tab')), findsOneWidget);
    });

    testWidgets(
      'إضافة موعد لليوم يظهر في الشبكة واللوحة والقاعدة ثم تم/تراجع وحذف',
      (tester) async {
        await boot(tester);
        await tester.tap(find.text('الحجوزات'), warnIfMissed: false);
        await settle(tester);

        // افتح نموذج الإضافة واملأه.
        await tester.tap(
          find.byKey(const Key('appt-add-toggle')),
          warnIfMissed: false,
        );
        await settle(tester);
        await tester.enterText(find.byKey(const Key('appt-name')), 'سعاد');
        await tester.enterText(
          find.byKey(const Key('appt-phone')),
          '0918888888',
        );
        await tester.enterText(find.byKey(const Key('appt-service')), 'كشف');
        // التاريخ افتراضياً اليوم من _resetForm.
        await tester.ensureVisible(find.byKey(const Key('appt-save')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('appt-save')),
          warnIfMissed: false,
        );
        await settle(tester);

        // القاعدة: موعد pending بمفتاح مريض.
        final c = container();
        final saved = c.read(reposProvider).appointments.getAll().single;
        c.dispose();
        expect(saved['name'], 'سعاد');
        expect(saved['status'], 'pending');
        expect('${saved['patient_id']}'.isNotEmpty, isTrue);
        final today = getCurrentDate();
        expect(saved['date'], today);

        // خلية اليوم تحمل العدّاد واللوحة تفتح ببطاقة الموعد.
        await tester.ensureVisible(find.byKey(Key('cal-day-$today')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(Key('cal-day-$today')),
          warnIfMissed: false,
        );
        await settle(tester);
        expect(find.textContaining('1 موعد'), findsOneWidget);
        expect(find.textContaining('سعاد'), findsWidgets);
        expect(find.textContaining('⏱ قادم'), findsOneWidget);

        final id = '${saved['id']}';
        // تم ⇒ مكتمل، ثم تراجع.
        await tester.ensureVisible(find.byKey(Key('appt-done-$id')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key('appt-done-$id')), warnIfMissed: false);
        await settle(tester);
        var c2 = container();
        expect(
          c2.read(reposProvider).appointments.getById(id)!['status'],
          'completed',
        );
        c2.dispose();
        await tester.ensureVisible(find.byKey(Key('appt-undone-$id')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(Key('appt-undone-$id')),
          warnIfMissed: false,
        );
        await settle(tester);
        c2 = container();
        expect(
          c2.read(reposProvider).appointments.getById(id)!['status'],
          'upcoming',
        );
        c2.dispose();

        // م164 — الحذف صار في ورقة الإجراءات السريعة: افتح البطاقة أولاً.
        await tester.ensureVisible(find.byKey(Key('appt-row-$id')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key('appt-row-$id')), warnIfMissed: false);
        await settle(tester);
        // حذف بعداد dcConfirm (النوع appt، الافتراضي 3 ثوانٍ).
        await tester.ensureVisible(find.byKey(Key('appt-del-$id')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key('appt-del-$id')), warnIfMissed: false);
        await settle(tester);
        expect(find.byKey(const Key('dc-countdown')), findsOneWidget);
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(seconds: 1));
        }
        await tester.tap(
          find.byKey(const Key('dc-confirm')),
          warnIfMissed: false,
        );
        await settle(tester);
        final c3 = container();
        addTearDown(c3.dispose);
        expect(c3.read(reposProvider).appointments.getAll(), isEmpty);
      },
    );

    // م167 — حُذفت شريحة «موعد» من نموذج زيارة جديدة (قرار المالك)،
    // فذهب معها اختبار «موعد متابعة من شاشة الإضافة».

    testWidgets('إشعار مواعيد اليوم عند فتح التطبيق (apptNotif)', (
      tester,
    ) async {
      resetApptNotifGuard();
      await boot(
        tester,
        seed: (c) {
          c.read(reposProvider).appointments.upsertLocal({
            'id': 'a1',
            'name': 'وليد',
            'date': getCurrentDate(),
            'time': '10:00',
            'service': 'كشف',
            'status': 'pending',
          });
          c.read(reposProvider).appointments.upsertLocal({
            'id': 'a2',
            'name': 'ملغي',
            'date': getCurrentDate(),
            'status': 'cancelled',
          });
        },
      );
      await settle(tester);
      expect(find.byKey(const Key('appt-notif-dialog')), findsOneWidget);
      expect(find.textContaining('مواعيد اليوم'), findsOneWidget);
      expect(find.text('وليد'), findsOneWidget);
      expect(find.text('ملغي'), findsNothing); // الملغي مستبعد
      await tester.tap(
        find.byKey(const Key('appt-notif-ok')),
        warnIfMissed: false,
      );
      await settle(tester);
      expect(find.byKey(const Key('appt-notif-dialog')), findsNothing);
    });

    testWidgets('المدة (durationMin) بالهاتف تُحفظ ضمن upsertLocal للموعد', (
      tester,
    ) async {
      await boot(tester);
      await tester.tap(find.text('الحجوزات'), warnIfMissed: false);
      await settle(tester);

      await tester.tap(
        find.byKey(const Key('appt-add-toggle')),
        warnIfMissed: false,
      );
      await settle(tester);
      await tester.enterText(find.byKey(const Key('appt-name')), 'صاحب المدة');
      // حقل المدة الجديد (appt-duration).
      await tester.ensureVisible(find.byKey(const Key('appt-duration')));
      await tester.enterText(find.byKey(const Key('appt-duration')), '45');
      await tester.ensureVisible(find.byKey(const Key('appt-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('appt-save')), warnIfMissed: false);
      await settle(tester);

      final c = container();
      addTearDown(c.dispose);
      final saved = c.read(reposProvider).appointments.getAll().single;
      expect(saved['name'], 'صاحب المدة');
      // م: durationMin حقلٌ مرن في كتلة data — ينجو عبر prepareForStorage/
      // parseRowData ويُقرأ.
      expect((saved['durationMin'] as num).toInt(), 45);
      expect(saved['status'], 'pending');
    });

    testWidgets('نسخ الموعد بالهاتف: نموذجٌ مسبق التعبئة ثم صفٌّ جديد', (
      tester,
    ) async {
      final today = getCurrentDate();
      await boot(
        tester,
        seed: (c) {
          c.read(reposProvider).appointments.upsertLocal({
            'id': 'src1',
            'name': 'أصل الموعد',
            'phone': '0913000000',
            'date': today,
            'time': '10:00',
            'service': 'تنظيف',
            'notes': 'ملاحظة',
            'durationMin': 30,
            'status': 'pending',
            '_t': 'a',
          });
        },
      );
      await tester.tap(find.text('الحجوزات'), warnIfMissed: false);
      await settle(tester);

      // افتح لوحة اليوم بالنقر على خلية اليوم.
      await tester.ensureVisible(find.byKey(Key('cal-day-$today')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('cal-day-$today')), warnIfMissed: false);
      await settle(tester);

      // م164 — النسخ صار في ورقة الإجراءات: افتح بطاقة الموعد أولاً.
      await tester.ensureVisible(find.byKey(const Key('appt-row-src1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('appt-row-src1')),
          warnIfMissed: false);
      await settle(tester);
      // بند «نسخ الموعد» (appt-copy-src1) يفتح النموذج مسبق التعبئة.
      await tester.ensureVisible(find.byKey(const Key('appt-copy-src1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('appt-copy-src1')),
          warnIfMissed: false);
      await settle(tester);

      // النموذج مفتوحٌ مسبق التعبئة (اسم/مدة)، الوقت فارغ.
      final nameField =
          tester.widget<TextField>(find.byKey(const Key('appt-name')));
      expect(nameField.controller!.text, 'أصل الموعد');
      final durField =
          tester.widget<TextField>(find.byKey(const Key('appt-duration')));
      expect(durField.controller!.text, '30');

      await tester.ensureVisible(find.byKey(const Key('appt-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('appt-save')), warnIfMissed: false);
      await settle(tester);

      // صفّان: الأصل + النسخة بمعرّفٍ مختلف، والنسخة موعدٌ مفرد pending.
      final c = container();
      addTearDown(c.dispose);
      final all = c.read(reposProvider).appointments.getAll();
      expect(all.length, 2, reason: 'النسخ ينشئ صفاً جديداً');
      final copy = all.firstWhere((r) => '${r['id']}' != 'src1');
      expect(copy['id'], isNot('src1'));
      expect(copy['name'], 'أصل الموعد');
      expect(copy['service'], 'تنظيف');
      expect((copy['durationMin'] as num).toInt(), 30);
      expect(copy['status'], 'pending');
    });
  });
}
